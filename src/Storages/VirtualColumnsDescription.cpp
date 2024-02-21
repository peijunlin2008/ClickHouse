#include "Core/NamesAndTypes.h"
#include "DataTypes/Serializations/ISerialization.h"
#include "base/types.h"
#include <Storages/VirtualColumnsDescription.h>

namespace DB
{

namespace ErrorCodes
{
    extern const int DUPLICATE_COLUMN;
    extern const int NO_SUCH_COLUMN_IN_TABLE;
}

VirtualColumnDescription::VirtualColumnDescription(
    String name_, DataTypePtr type_, ASTPtr codec_, String comment_, VirtualsKind kind_)
    : ColumnDescription(std::move(name_), std::move(type_), std::move(codec_), std::move(comment_))
    , kind(kind_)
{
}

void VirtualColumnsDescription::add(VirtualColumnDescription desc_)
{
    auto [it, inserted] = container.emplace(std::move(desc_));
    if (!inserted)
        throw Exception(ErrorCodes::DUPLICATE_COLUMN, "Virtual column {} already exists", it->name);
}

void VirtualColumnsDescription::addEphemeral(String name, DataTypePtr type, String comment)
{
    add({std::move(name), std::move(type), nullptr, std::move(comment), VirtualsKind::Ephemeral});
}

void VirtualColumnsDescription::addPersistent(String name, DataTypePtr type, ASTPtr codec, String comment)
{
    add({std::move(name), std::move(type), std::move(codec), std::move(comment), VirtualsKind::Persistent});
}

NamesAndTypesList VirtualColumnsDescription::get(VirtualsKind kind) const
{
    NamesAndTypesList result;
    for (const auto & column : container)
        if (static_cast<UInt8>(column.kind) & static_cast<UInt8>(kind))
            result.emplace_back(column.name, column.type);
    return result;
}

std::optional<NameAndTypePair> VirtualColumnsDescription::tryGet(const String & name, VirtualsKind kind) const
{
    auto it = container.find(name);
    if (it != container.end() && (static_cast<UInt8>(it->kind) & static_cast<UInt8>(kind)))
        return NameAndTypePair{it->name, it->type};
    return {};
}

NameAndTypePair VirtualColumnsDescription::get(const String & name, VirtualsKind kind) const
{
    auto column = tryGet(name, kind);
    if (!column)
        throw Exception(ErrorCodes::NO_SUCH_COLUMN_IN_TABLE, "There is no virtual column {}", name);
    return *column;
}

std::optional<VirtualColumnDescription> VirtualColumnsDescription::tryGetDescription(const String & name, VirtualsKind kind) const
{
    auto it = container.find(name);
    if (it != container.end() && (static_cast<UInt8>(it->kind) & static_cast<UInt8>(kind)))
        return *it;
    return {};
}

VirtualColumnDescription VirtualColumnsDescription::getDescription(const String & name, VirtualsKind kind) const
{
    auto column = tryGetDescription(name, kind);
    if (!column)
        throw Exception(ErrorCodes::NO_SUCH_COLUMN_IN_TABLE, "There is no virtual column {}", name);
    return *column;
}

NamesAndTypesList VirtualColumnsDescription::getNamesAndTypesList() const
{
    NamesAndTypesList result;
    for (const auto & desc : container)
        result.emplace_back(desc.name, desc.type);
    return result;
}

Block VirtualColumnsDescription::getSampleBlock() const
{
    Block result;
    for (const auto & desc : container)
        result.insert({desc.type->createColumn(), desc.type, desc.name});
    return result;
}

}
