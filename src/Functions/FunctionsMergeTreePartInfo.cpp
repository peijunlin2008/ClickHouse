#include <Storages/MergeTree/MergeTreePartInfo.h>

#include <Functions/IFunction.h>
#include <Functions/FunctionHelpers.h>
#include <Functions/FunctionFactory.h>

#include <Columns/ColumnString.h>
#include <Columns/ColumnVector.h>
#include <Columns/ColumnFixedString.h>
#include <Columns/ColumnsNumber.h>
#include <Columns/ColumnTuple.h>

#include <DataTypes/DataTypesNumber.h>
#include <DataTypes/DataTypeLowCardinality.h>
#include <DataTypes/DataTypeTuple.h>

#include <Common/register_objects.h>

namespace DB
{

namespace ErrorCodes
{
    extern const int BAD_ARGUMENTS;
}

namespace
{

struct UnpackedPartSegments
{
    MergeTreePartInfo part_info;
    std::string prefix;
    std::string suffix;
};

std::optional<MergeTreePartInfo> tryParseMergeTreePartInfo(std::string_view data)
{
    return MergeTreePartInfo::tryParsePartName(data, MERGE_TREE_DATA_MIN_FORMAT_VERSION_WITH_CUSTOM_PARTITIONING);
}

[[noreturn]] void throwInvalidPartName(std::string_view data)
{
    throw Exception(ErrorCodes::BAD_ARGUMENTS, "Invalid MergeTree part name: '{}'.", data);
}

MergeTreePartInfo constructPartInfo(std::string_view data)
{
    if (auto info = tryParseMergeTreePartInfo(data))
        return std::move(info.value());

    throwInvalidPartName(data);
}

/// Tries to parse part name format: "<prefix>_<part_name>_<tryN>".
UnpackedPartSegments unpackPartName(std::string_view data)
{
    UnpackedPartSegments unpacked;

    /// prefix_name_tryN
    ///                 ^
    size_t right = data.size();
    size_t first_delimiter = data.find_first_of('_');
    size_t last_delimiter = data.find_last_of('_');
    size_t number_of_segments = std::ranges::count(data, '_') + 1;

    if (number_of_segments < 4)
        throwInvalidPartName(data);

    /// Process suffix first because it can be easily determined.
    if (data.substr(last_delimiter + 1).starts_with("try"))
    {
        unpacked.suffix = data.substr(last_delimiter + 1);
        right = last_delimiter;
        number_of_segments -= 1;
    }

    switch (number_of_segments)
    {
    case 6: /// prefix_partition_min_max_level_mutation
    {
        unpacked.prefix = data.substr(0, first_delimiter);
        unpacked.part_info = constructPartInfo(data.substr(first_delimiter + 1, right - (first_delimiter + 1)));
        break;
    }
    case 5: /// prefix_partition_min_max_level or partition_min_max_level_mutation
    {
        /// Still incorrect if partition can be parsed as number and will be < min
        if (auto info = tryParseMergeTreePartInfo(data.substr(0, right)))
        {
            unpacked.prefix = "";
            unpacked.part_info = std::move(info.value());
            break;
        }

        if (auto info = tryParseMergeTreePartInfo(data.substr(first_delimiter + 1, right - (first_delimiter + 1))))
        {
            unpacked.prefix = data.substr(0, first_delimiter);
            unpacked.part_info = std::move(info.value());
            break;
        }

        throwInvalidPartName(data);
    }
    case 4: /// partition_min_max_level
    {
        unpacked.part_info = constructPartInfo(data.substr(0, right));
        break;
    }
    default:
        throwInvalidPartName(data);
    }

    return unpacked;
}

bool isAnyStringType(const IDataType & data_type)
{
    return isStringOrFixedString(removeLowCardinality(data_type.getPtr()));
}

class FunctionMergeTreePartCoverage : public IFunction
{
    static MergeTreePartInfo constructCoveringPart(const ColumnPtr & covering_column, size_t row_number)
    {
        if (isColumnConst(*covering_column))
            return unpackPartName(covering_column->getDataAt(0).toView()).part_info;

        return unpackPartName(covering_column->getDataAt(row_number).toView()).part_info;
    }

public:
    static constexpr auto name = "isMergeTreePartCoveredBy";
    String getName() const override { return name; }

    static FunctionPtr create(ContextPtr) { return std::make_shared<FunctionMergeTreePartCoverage>(); }

    bool useDefaultImplementationForLowCardinalityColumns() const override { return false; }
    bool useDefaultImplementationForSparseColumns() const override { return false; }
    bool isSuitableForShortCircuitArgumentsExecution(const DataTypesWithConstInfo &) const override { return false; }
    size_t getNumberOfArguments() const override { return 2; }

    DataTypePtr getReturnTypeImpl(const ColumnsWithTypeAndName & arguments) const override
    {
        validateFunctionArguments(*this, arguments, FunctionArgumentDescriptors{
            {"nested_part", static_cast<FunctionArgumentDescriptor::TypeValidator>(&isAnyStringType), nullptr, "String or FixedString or LowCardinality String"},
            {"covering_part", static_cast<FunctionArgumentDescriptor::TypeValidator>(&isAnyStringType), nullptr, "String or FixedString or LowCardinality String"}
        });

        return std::make_shared<DataTypeUInt8>();
    }

    ColumnPtr executeImpl(const ColumnsWithTypeAndName & arguments, const DataTypePtr &, size_t input_rows_count) const override
    {
        auto result_column = ColumnUInt8::create();
        const ColumnPtr & input_column = arguments.front().column;

        for (size_t i = 0; i < input_rows_count; ++i)
        {
            const auto part_info = unpackPartName(input_column->getDataAt(i).toView()).part_info;
            const auto covering_part = constructCoveringPart(arguments[1].column, i);
            result_column->insertValue(covering_part.contains(part_info));
        }

        return result_column;
    }
};

class FunctionMergeTreePartInfo : public IFunction
{
public:
    static constexpr auto name = "mergeTreePartInfo";
    String getName() const override { return name; }

    static FunctionPtr create(ContextPtr) { return std::make_shared<FunctionMergeTreePartInfo>(); }

    bool useDefaultImplementationForLowCardinalityColumns() const override { return false; }
    bool useDefaultImplementationForSparseColumns() const override { return false; }
    bool isSuitableForShortCircuitArgumentsExecution(const DataTypesWithConstInfo &) const override { return false; }
    size_t getNumberOfArguments() const override { return 1; }

    DataTypePtr getReturnTypeImpl(const ColumnsWithTypeAndName & arguments) const override
    {
        validateFunctionArguments(*this, arguments, FunctionArgumentDescriptors{
            {"part_name", static_cast<FunctionArgumentDescriptor::TypeValidator>(&isAnyStringType), nullptr, "String or FixedString or LowCardinality String"}
        });

        DataTypes types = {
            std::make_shared<DataTypeString>(),
            std::make_shared<DataTypeString>(),
            std::make_shared<DataTypeString>(),
            std::make_shared<DataTypeInt64>(),
            std::make_shared<DataTypeInt64>(),
            std::make_shared<DataTypeInt64>(),
            std::make_shared<DataTypeInt64>(),
        };

        Names names = {
            "partition_id",
            "prefix",
            "suffix",
            "min_block",
            "max_block",
            "level",
            "mutation",
        };

        return std::make_shared<DataTypeTuple>(std::move(types), std::move(names));
    }

    ColumnPtr executeImpl(const ColumnsWithTypeAndName & arguments, const DataTypePtr &, size_t input_rows_count) const override
    {
        const ColumnPtr & input_column = arguments[0].column;

        auto partition_column = ColumnString::create();
        auto prefix_column = ColumnString::create();
        auto suffix_column = ColumnString::create();
        auto min_block_column = ColumnInt64::create();
        auto max_block_column = ColumnInt64::create();
        auto level_column = ColumnInt64::create();
        auto mutation_column = ColumnInt64::create();

        for (size_t i = 0; i < input_rows_count; ++i)
        {
            const auto [part_info, prefix, suffix] = unpackPartName(input_column->getDataAt(i).toView());

            partition_column->insertData(part_info.getPartitionId().data(), part_info.getPartitionId().size());
            prefix_column->insertData(prefix.data(), prefix.size());
            suffix_column->insertData(suffix.data(), suffix.size());
            min_block_column->insertValue(part_info.min_block);
            max_block_column->insertValue(part_info.max_block);
            level_column->insertValue(part_info.level);
            mutation_column->insertValue(part_info.mutation);
        }

        return ColumnTuple::create(Columns{
            std::move(partition_column),
            std::move(prefix_column),
            std::move(suffix_column),
            std::move(min_block_column),
            std::move(max_block_column),
            std::move(level_column),
            std::move(mutation_column),
        });
    }
};

}

REGISTER_FUNCTION(MergeTreePartInfoTools)
{
    factory.registerFunction<FunctionMergeTreePartCoverage>(
        FunctionDocumentation{
            .description = "Checks if one MergeTree part covers another",
            .introduced_in = {25, 6},
            .category = FunctionDocumentation::Category::Introspection,
        },
        FunctionFactory::Case::Insensitive);

    factory.registerFunction<FunctionMergeTreePartInfo>(
        FunctionDocumentation{
            .description = "Represents String value as a MergeTreePartInfo structure",
            .introduced_in = {25, 6},
            .category = FunctionDocumentation::Category::Introspection,
        },
        FunctionFactory::Case::Insensitive);
}

}
