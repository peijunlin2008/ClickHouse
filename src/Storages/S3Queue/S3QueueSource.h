#pragma once
#include "config.h"

#include <Common/ZooKeeper/ZooKeeper.h>
#include <Processors/ISource.h>
#include <Storages/S3Queue/S3QueueMetadata.h>
#include <Storages/ObjectStorage/StorageObjectStorage.h>
#include <Storages/ObjectStorage/StorageObjectStorageSource.h>
#include <Interpreters/S3QueueLog.h>


namespace Poco { class Logger; }

namespace DB
{

struct ObjectMetadata;

class StorageS3QueueSource : public ISource, WithContext
{
public:
    using Storage = StorageObjectStorage;
    using ConfigurationPtr = Storage::ConfigurationPtr;
    using GlobIterator = StorageObjectStorageSource::GlobIterator;
    using ZooKeeperGetter = std::function<zkutil::ZooKeeperPtr()>;
    using RemoveFileFunc = std::function<void(std::string)>;
    using FileStatusPtr = S3QueueMetadata::FileStatusPtr;
    using ReaderHolder = StorageObjectStorageSource::ReaderHolder;
    using Metadata = S3QueueMetadata;
    using ObjectInfo = StorageObjectStorageSource::ObjectInfo;
    using ObjectInfoPtr = std::shared_ptr<ObjectInfo>;
    using ObjectInfos = std::vector<ObjectInfoPtr>;

    struct S3QueueObjectInfo : public ObjectInfo
    {
        S3QueueObjectInfo(
            const ObjectInfo & object_info,
            Metadata::FileMetadataPtr file_metadata_);

        Metadata::FileMetadataPtr file_metadata;
    };

    class FileIterator : public StorageObjectStorageSource::IIterator
    {
    public:
        FileIterator(
            std::shared_ptr<S3QueueMetadata> metadata_,
            std::unique_ptr<GlobIterator> glob_iterator_,
            std::atomic<bool> & shutdown_called_,
            LoggerPtr logger_);

        bool isFinished() const;

        /// Note:
        /// List results in s3 are always returned in UTF-8 binary order.
        /// (https://docs.aws.amazon.com/AmazonS3/latest/userguide/ListingKeysUsingAPIs.html)
        ObjectInfoPtr nextImpl(size_t processor) override;

        size_t estimatedKeysCount() override;

        void returnForRetry(ObjectInfoPtr object_info);

    private:
        using Bucket = S3QueueMetadata::Bucket;
        using Processor = S3QueueMetadata::Processor;

        const std::shared_ptr<S3QueueMetadata> metadata;
        const std::unique_ptr<GlobIterator> glob_iterator;

        std::atomic<bool> & shutdown_called;
        std::mutex mutex;
        LoggerPtr log;

        std::mutex buckets_mutex;
        struct ListedKeys
        {
            std::deque<ObjectInfoPtr> keys;
            std::optional<Processor> processor;
        };
        std::unordered_map<Bucket, ListedKeys> listed_keys_cache;
        bool iterator_finished = false;
        std::unordered_map<size_t, S3QueueOrderedFileMetadata::BucketHolderPtr> bucket_holders;

        /// Only for processing without buckets.
        std::deque<ObjectInfoPtr> objects_to_retry;

        std::pair<ObjectInfoPtr, S3QueueOrderedFileMetadata::BucketInfoPtr> getNextKeyFromAcquiredBucket(size_t processor);
    };

    StorageS3QueueSource(
        String name_,
        size_t processor_id_,
        const Block & header_,
        std::unique_ptr<StorageObjectStorageSource> internal_source_,
        std::shared_ptr<S3QueueMetadata> files_metadata_,
        const S3QueueAction & action_,
        RemoveFileFunc remove_file_func_,
        const NamesAndTypesList & requested_virtual_columns_,
        ContextPtr context_,
        const std::atomic<bool> & shutdown_called_,
        const std::atomic<bool> & table_is_being_dropped_,
        std::shared_ptr<S3QueueLog> s3_queue_log_,
        const StorageID & storage_id_,
        LoggerPtr log_,
        size_t max_processed_files_before_commit_,
        size_t max_processed_rows_before_commit_,
        size_t max_processed_bytes_before_commit_,
        size_t max_processing_time_sec_before_commit_,
        bool commit_once_processed_);

    static Block getHeader(Block sample_block, const std::vector<NameAndTypePair> & requested_virtual_columns);

    String getName() const override;

    Chunk generate() override;

    void commit(bool success, const std::string & exception = {});

private:
    const String name;
    const size_t processor_id;
    const S3QueueAction action;
    const std::shared_ptr<S3QueueMetadata> files_metadata;
    const std::shared_ptr<StorageObjectStorageSource> internal_source;
    const NamesAndTypesList requested_virtual_columns;
    const std::atomic<bool> & shutdown_called;
    const std::atomic<bool> & table_is_being_dropped;
    const std::shared_ptr<S3QueueLog> s3_queue_log;
    const StorageID storage_id;
    const size_t max_processed_files_before_commit;
    const size_t max_processed_rows_before_commit;
    const size_t max_processed_bytes_before_commit;
    const size_t max_processing_time_sec_before_commit;
    const bool commit_once_processed;

    RemoveFileFunc remove_file_func;
    LoggerPtr log;

    std::vector<Metadata::FileMetadataPtr> processed_files;
    std::vector<Metadata::FileMetadataPtr> failed_files;

    ReaderHolder reader;
    std::future<ReaderHolder> reader_future;
    std::atomic<bool> initialized{false};

    size_t processed_rows_from_file = 0;
    size_t total_processed_rows = 0;
    size_t total_processed_bytes = 0;

    Stopwatch total_stopwatch {CLOCK_MONOTONIC_COARSE};

    S3QueueOrderedFileMetadata::BucketHolderPtr current_bucket_holder;

    Chunk generateImpl();
    void applyActionAfterProcessing(const String & path);
    void appendLogElement(const std::string & filename, S3QueueMetadata::FileStatus & file_status_, size_t processed_rows, bool processed);
    void lazyInitialize(size_t processor);
};

}
