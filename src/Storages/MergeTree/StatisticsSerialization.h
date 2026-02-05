#pragma once

#include <Storages/Statistics/Statistics.h>
#include <IO/WriteBuffer.h>

namespace DB
{

class IDataPartStorage;
struct WriteSettings;
struct MergeTreeDataPartChecksums;
class WriteBufferFromFileBase;

std::unique_ptr<WriteBufferFromFileBase> serializeStatisticsPacked(
    IDataPartStorage & data_part_storage,
    MergeTreeDataPartChecksums & out_checksums,
    const ColumnsStatistics & statistics,
    const WriteSettings & write_settings);

void serializeStatisticsWide(
    IDataPartStorage & data_part_storage,
    MergeTreeDataPartChecksums & out_checksums,
    const ColumnsStatistics & statistics,
    const WriteSettings & write_settings);

}
