#pragma once

#include "config.h"

#if USE_DELTA_KERNEL_RS

#include <Core/Types.h>
#include <IO/S3/URI.h>
#include <Common/Logger.h>
#include <Storages/ObjectStorage/StorageObjectStorage.h>
#include <Storages/ObjectStorage/IObjectIterator.h>
#include <Storages/ObjectStorage/DataLakes/IDataLakeMetadata.h>
#include <Storages/ObjectStorage/DataLakes/DeltaLake/KernelPointerWrapper.h>
#include <Storages/ObjectStorage/DataLakes/DeltaLake/KernelHelper.h>
#include <boost/noncopyable.hpp>
#include "delta_kernel_ffi.hpp"

namespace DeltaLake
{

/**
 * A class representing DeltaLake table snapshot -
 * a snapshot of table state, its schema, data files, etc.
 */
class TableSnapshot
{
public:
    static constexpr auto LATEST_SNAPSHOT_VERSION = -1;

    explicit TableSnapshot(
        KernelHelperPtr helper_,
        DB::ObjectStoragePtr object_storage_,
        DB::ContextPtr context_,
        LoggerPtr log_);

    /// Get snapshot version.
    size_t getVersion() const;

    std::optional<size_t> getTotalRows() const;
    std::optional<size_t> getTotalBytes() const;

    /// Update snapshot to latest version.
    void updateToLatestVersion(const DB::ContextPtr & context);

    /// Iterate over DeltaLake data files.
    DB::ObjectIterator iterate(
        const DB::ActionsDAG * filter_dag,
        DB::IDataLakeMetadata::FileProgressCallback callback,
        size_t list_batch_size);

    /// Get schema from DeltaLake table metadata.
    const DB::NamesAndTypesList & getTableSchema() const;
    /// Get read schema derived from data files.
    /// (In most cases it would be the same as table schema).
    const DB::NamesAndTypesList & getReadSchema() const;
    /// DeltaLake stores partition columns values not in the data files,
    /// but in data file path directory names.
    /// Therefore "table schema" would contain partition columns,
    /// but "read schema" would not.
    const DB::Names & getPartitionColumns() const;
    const DB::NameToNameMap & getPhysicalNamesMap() const;

    DB::ObjectStoragePtr getObjectStorage() const { return object_storage; }
private:
    class Iterator;

    using KernelExternEngine = KernelPointerWrapper<ffi::SharedExternEngine, ffi::free_engine>;
    using KernelSnapshot = KernelPointerWrapper<ffi::SharedSnapshot, ffi::free_snapshot>;
    using KernelScan = KernelPointerWrapper<ffi::SharedScan, ffi::free_scan>;
    using KernelScanMetadataIterator = KernelPointerWrapper<ffi::SharedScanMetadataIterator, ffi::free_scan_metadata_iter>;

    using TableSchema = DB::NamesAndTypesList;
    using ReadSchema = DB::NamesAndTypesList;

    const KernelHelperPtr helper;
    const DB::ObjectStoragePtr object_storage;
    const LoggerPtr log;

    bool enable_expression_visitor_logging;
    bool throw_on_engine_visitor_error;
    bool enable_engine_predicate;
    std::optional<size_t> snapshot_version_to_read;

    struct KernelSnapshotState : private boost::noncopyable
    {
        KernelSnapshotState(const IKernelHelper & helper_, std::optional<size_t> snapshot_version_);

        KernelExternEngine engine;
        KernelSnapshot snapshot;
        KernelScan scan;
        size_t snapshot_version;
    };
    mutable std::shared_ptr<KernelSnapshotState> kernel_snapshot_state;

    struct SchemaInfo
    {
        /// Snapshot version
        size_t version;
        /// Table logical schema
        TableSchema table_schema;
        /// Table read schema
        ReadSchema read_schema;
        /// Mapping for physical names of parquet data files
        DB::NameToNameMap physical_names_map;
        /// Partition columns list (not stored in read schema)
        DB::Names partition_columns;
    };
    mutable std::optional<SchemaInfo> schema;

    struct SnapshotStats
    {
        /// Snapshot version
        size_t version;
        /// Total number of bytes in table
        std::optional<size_t> total_bytes;
        /// Total number of rows in table
        std::optional<size_t> total_rows;
    };
    mutable std::optional<SnapshotStats> snapshot_stats;

    void initSnapshot(bool recreate = false) const;
    void initSchema() const;

    SnapshotStats getSnapshotStats() const;
    SnapshotStats getSnapshotStatsImpl() const;

    void updateSettings(const DB::ContextPtr & context);
};

}

#endif
