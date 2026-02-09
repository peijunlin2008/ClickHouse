#include <Storages/MergeTree/StatisticsSerialization.h>
#include <IO/WriteBuffer.h>
#include <IO/PackedFilesWriter.h>
#include <IO/HashingWriteBuffer.h>
#include <Compression/CompressedWriteBuffer.h>
#include <Storages/MergeTree/IDataPartStorage.h>

namespace DB
{

std::unique_ptr<WriteBufferFromFileBase> serializeStatisticsPacked(
    IDataPartStorage & data_part_storage,
    MergeTreeDataPartChecksums & out_checksums,
    const ColumnsStatistics & statistics,
    const CompressionCodecPtr & compression_codec,
    const WriteSettings & write_settings)
{
    PackedFilesWriter packed_writer;

    for (const auto & [column_name, stat] : statistics)
    {
        String filename = column_name + STATS_FILE_SUFFIX;
        auto out = packed_writer.writeFile(filename, write_settings);

        CompressedWriteBuffer compressor(*out, compression_codec, 1024 * 1024);
        stat->serialize(compressor);
        compressor.finalize();
        out->finalize();
    }

    String statistics_filename = String(ColumnsStatistics::FILENAME);
    auto out_packed = data_part_storage.writeFile(statistics_filename, 4096, write_settings);
    HashingWriteBuffer out_hashing_packed(*out_packed);

    packed_writer.finalize(out_hashing_packed);
    out_hashing_packed.finalize();

    out_checksums.files[statistics_filename].file_size = out_hashing_packed.count();
    out_checksums.files[statistics_filename].file_hash = out_hashing_packed.getHash();
    out_packed->preFinalize();

    return out_packed;
}

}
