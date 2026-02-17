#include <Disks/DiskObjectStorage/MetadataStorages/NormalizedPath.h>

#include <Common/Exception.h>

namespace DB
{

namespace ErrorCodes
{
    extern const int LOGICAL_ERROR;
}

NormalizedPath NormalizedPath::parent_path() const
{
    return NormalizedPath{std::filesystem::path::parent_path()};
}

NormalizedPath normalizePath(std::string path)
{
    auto lexically_normal = std::filesystem::path(path).lexically_normal();
    auto filtered_path = lexically_normal.string();

#ifndef NDEBUG
    /// Check that paths do not use .. anytime
    bool is_valid_path = true;
    for (const auto & step : lexically_normal)
        if (step.string() == "..")
            is_valid_path = false;

    if (!is_valid_path)
        throw Exception(ErrorCodes::LOGICAL_ERROR, "Path '{}' should not be used in disks", lexically_normal.string());
#endif

    /// Remove leftovers from the ends
    std::string_view normalized_path = filtered_path;
    while (normalized_path.ends_with('/') || normalized_path.ends_with('.'))
        normalized_path.remove_suffix(1);

    while (normalized_path.starts_with('/') || normalized_path.starts_with('.'))
        normalized_path.remove_prefix(1);

    return NormalizedPath{normalized_path};
}

}
