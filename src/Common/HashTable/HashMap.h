#pragma once

#include <Common/HashTable/Hash.h>
#include <Common/HashTable/HashTable.h>
#include <Common/HashTable/HashTableAllocator.h>
#include <Common/HashTable/Prefetching.h>


/** NOTE HashMap could only be used for memmoveable (position independent) types.
  * Example: std::string is not position independent in libstdc++ with C++11 ABI or in libc++.
  * Also, key in hash table must be of type, that zero bytes is compared equals to zero key.
  *
  * Please keep in sync with PackedHashMap.h
  */

namespace DB
{
namespace ErrorCodes
{
    extern const int LOGICAL_ERROR;
}
}

struct NoInitTag
{
};

/// A pair that does not initialize the elements, if not needed.
template <typename First, typename Second>
struct PairNoInit
{
    First first;
    Second second;

    PairNoInit() {} /// NOLINT

    template <typename FirstValue>
    PairNoInit(FirstValue && first_, NoInitTag)
        : first(std::forward<FirstValue>(first_))
    {
    }

    template <typename FirstValue, typename SecondValue>
    PairNoInit(FirstValue && first_, SecondValue && second_)
        : first(std::forward<FirstValue>(first_))
        , second(std::forward<SecondValue>(second_))
    {
    }

    auto operator<=>(const PairNoInit &) const = default;
};

template <typename First, typename Second>
PairNoInit<std::decay_t<First>, std::decay_t<Second>> makePairNoInit(First && first, Second && second)
{
    return PairNoInit<std::decay_t<First>, std::decay_t<Second>>(std::forward<First>(first), std::forward<Second>(second));
}


template <typename Key, typename TMapped, typename Hash, typename TState = HashTableNoState, typename Pair = PairNoInit<Key, TMapped>>
struct HashMapCell
{
    using Mapped = TMapped;
    using State = TState;

    using value_type = Pair;
    using mapped_type = Mapped;
    using key_type = Key;

    value_type value;

    HashMapCell() = default;
    HashMapCell(const Key & key_, const State &) : value(key_, NoInitTag()) {}
    HashMapCell(const value_type & value_, const State &) : value(value_) {}

    /// Get the key (externally).
    const Key & getKey() const { return value.first; }
    Mapped & getMapped() { return value.second; }
    const Mapped & getMapped() const { return value.second; }
    const value_type & getValue() const { return value; }

    /// Get the key (internally).
    static const Key & getKey(const value_type & value) { return value.first; }

    bool keyEquals(const Key & key_) const { return bitEquals(value.first, key_); }
    bool keyEquals(const Key & key_, size_t /*hash_*/) const { return bitEquals(value.first, key_); }
    bool keyEquals(const Key & key_, size_t /*hash_*/, const State & /*state*/) const { return bitEquals(value.first, key_); }

    void setHash(size_t /*hash_value*/) {}
    size_t getHash(const Hash & hash) const { return hash(value.first); }

    bool isZero(const State & state) const { return isZero(value.first, state); }
    static bool isZero(const Key & key, const State & /*state*/) { return ZeroTraits::check(key); }

    /// Set the key value to zero.
    void setZero() { ZeroTraits::set(value.first); }

    /// Do I need to store the zero key separately (that is, can a zero key be inserted into the hash table).
    static constexpr bool need_zero_value_storage = true;

    void setMapped(const value_type & value_) { value.second = value_.second; }

    /// Serialization, in binary and text form.
    void write(DB::WriteBuffer & wb) const
    {
        DB::writeBinary(value.first, wb);
        DB::writeBinary(value.second, wb);
    }

    void writeText(DB::WriteBuffer & wb) const
    {
        DB::writeDoubleQuoted(value.first, wb);
        DB::writeChar(',', wb);
        DB::writeDoubleQuoted(value.second, wb);
    }

    /// Deserialization, in binary and text form.
    void read(DB::ReadBuffer & rb)
    {
        DB::readBinary(value.first, rb);
        DB::readBinary(value.second, rb);
    }

    void readText(DB::ReadBuffer & rb)
    {
        DB::readDoubleQuoted(value.first, rb);
        DB::assertChar(',', rb);
        DB::readDoubleQuoted(value.second, rb);
    }

    template <size_t I>
    auto & get() & {
        if constexpr (I == 0) return value.first;
        else if constexpr (I == 1) return value.second;
    }

    template <size_t I>
    auto const & get() const & {
        if constexpr (I == 0) return value.first;
        else if constexpr (I == 1) return value.second;
    }

    template <size_t I>
    auto && get() && {
        if constexpr (I == 0) return std::move(value.first);
        else if constexpr (I == 1) return std::move(value.second);
    }

};

namespace std
{

    template <typename Key, typename TMapped, typename Hash, typename TState, typename Pair>
    struct tuple_size<HashMapCell<Key, TMapped, Hash, TState, Pair>> : std::integral_constant<size_t, 2> { };

    template <typename Key, typename TMapped, typename Hash, typename TState, typename Pair>
    struct tuple_element<0, HashMapCell<Key, TMapped, Hash, TState, Pair>> { using type = Key; };

    template <typename Key, typename TMapped, typename Hash, typename TState, typename Pair>
    struct tuple_element<1, HashMapCell<Key, TMapped, Hash, TState, Pair>> { using type = TMapped; };
}

template <typename Key, typename TMapped, typename Hash, typename TState = HashTableNoState>
struct HashMapCellWithSavedHash : public HashMapCell<Key, TMapped, Hash, TState>
{
    using Base = HashMapCell<Key, TMapped, Hash, TState>;

    size_t saved_hash;

    using Base::Base;

    bool keyEquals(const Key & key_) const { return bitEquals(this->value.first, key_); }
    bool keyEquals(const Key & key_, size_t hash_) const { return saved_hash == hash_ && bitEquals(this->value.first, key_); }
    bool keyEquals(const Key & key_, size_t hash_, const typename Base::State &) const { return keyEquals(key_, hash_); }

    void setHash(size_t hash_value) { saved_hash = hash_value; }
    size_t getHash(const Hash & /*hash_function*/) const { return saved_hash; }
};

template <
    typename Key,
    typename Cell,
    typename Hash = DefaultHash<Key>,
    typename Grower = HashTableGrowerWithPrecalculation<>,
    typename Allocator = HashTableAllocator>
class HashMapTable : public HashTable<Key, Cell, Hash, Grower, Allocator>
{
public:
    using Self = HashMapTable;
    using Base = HashTable<Key, Cell, Hash, Grower, Allocator>;
    using LookupResult = typename Base::LookupResult;
    using Iterator = typename Base::iterator;

    using Base::Base;
    using Base::prefetch;

    /// Merge every cell's value of current map into the destination map via emplace.
    ///  Func should have signature void(Mapped & dst, Mapped & src, bool emplaced).
    ///  Each filled cell in current map will invoke func once. If that map doesn't
    ///  have a key equals to the given cell, a new cell gets emplaced into that map,
    ///  and func is invoked with the third argument emplaced set to true. Otherwise
    ///  emplaced is set to false.
    template <typename Func, bool prefetch = false>
    void ALWAYS_INLINE mergeToViaEmplace(Self & that, Func && func)
    {
        DB::PrefetchingHelper prefetching;
        size_t prefetch_look_ahead = DB::PrefetchingHelper::getInitialLookAheadValue();

        size_t i = 0;
        auto prefetch_it = advanceIterator(this->begin(), prefetch_look_ahead);

        for (auto it = this->begin(), end = this->end(); it != end; ++it, ++i)
        {
            if constexpr (prefetch)
            {
                if (i == DB::PrefetchingHelper::iterationsToMeasure())
                {
                    prefetch_look_ahead = prefetching.calcPrefetchLookAhead();
                    prefetch_it = advanceIterator(prefetch_it, prefetch_look_ahead - DB::PrefetchingHelper::getInitialLookAheadValue());
                }

                if (prefetch_it != end)
                {
                    that.prefetchByHash(prefetch_it.getHash());
                    ++prefetch_it;
                }
            }

            typename Self::LookupResult res_it;
            bool inserted;
            that.emplace(Cell::getKey(it->getValue()), res_it, inserted, it.getHash());
            func(res_it->getMapped(), it->getMapped(), inserted);
        }
    }

    /// Merge every cell's value of current map into the destination map via find.
    ///  Func should have signature void(Mapped & dst, Mapped & src, bool exist).
    ///  Each filled cell in current map will invoke func once. If that map doesn't
    ///  have a key equals to the given cell, func is invoked with the third argument
    ///  exist set to false. Otherwise exist is set to true.
    template <typename Func>
    void ALWAYS_INLINE mergeToViaFind(Self & that, Func && func)
    {
        for (auto it = this->begin(), end = this->end(); it != end; ++it)
        {
            auto res_it = that.find(Cell::getKey(it->getValue()), it.getHash());
            if (!res_it)
                func(it->getMapped(), it->getMapped(), false);
            else
                func(res_it->getMapped(), it->getMapped(), true);
        }
    }

    /// Call func(const Key &, Mapped &) for each hash map element.
    template <typename Func>
    void forEachValue(Func && func)
    {
        for (auto & v : *this)
            func(v.getKey(), v.getMapped());
    }

    /// Call func(Mapped &) for each hash map element.
    template <typename Func>
    void forEachMapped(Func && func)
    {
        for (auto & v : *this)
            func(v.getMapped());
    }

    typename Cell::Mapped & ALWAYS_INLINE operator[](const Key & x)
    {
        LookupResult it;
        bool inserted;
        this->emplace(x, it, inserted);

        /** It may seem that initialization is not necessary for POD-types (or __has_trivial_constructor),
          *  since the hash table memory is initially initialized with zeros.
          * But, in fact, an empty cell may not be initialized with zeros in the following cases:
          * - ZeroValueStorage (it only zeros the key);
          * - after resizing and moving a part of the cells to the new half of the hash table, the old cells also have only the key to zero.
          *
          * On performance, there is almost always no difference, due to the fact that it->second is usually assigned immediately
          *  after calling `operator[]`, and since `operator[]` is inlined, the compiler removes unnecessary initialization.
          *
          * Sometimes due to initialization, the performance even grows. This occurs in code like `++map[key]`.
          * When we do the initialization, for new cells, it's enough to make `store 1` right away.
          * And if we did not initialize, then even though there was zero in the cell,
          *  the compiler can not guess about this, and generates the `load`, `increment`, `store` code.
          */
        if (inserted)
            new (reinterpret_cast<void*>(&it->getMapped())) typename Cell::Mapped();

        return it->getMapped();
    }

    /// Only inserts the value if key isn't already present
    void ALWAYS_INLINE insertIfNotPresent(const Key & x, const typename Cell::Mapped & value)
    {
        LookupResult it;
        bool inserted;
        this->emplace(x, it, inserted);
        if (inserted)
        {
            new (&it->getMapped()) typename Cell::Mapped();
            it->getMapped() = value;
        }
    }

    const typename Cell::Mapped & ALWAYS_INLINE at(const Key & x) const
    {
        if (auto it = this->find(x); it != this->end())
            return it->getMapped();
        throw DB::Exception(DB::ErrorCodes::LOGICAL_ERROR, "Cannot find element in HashMap::at method");
    }

private:
    Iterator advanceIterator(Iterator it, size_t n)
    {
        size_t i = 0;
        while (i < n && it != this->end())
        {
            ++i;
            ++it;
        }
        return it;
    }
};

namespace std
{

    template <typename Key, typename TMapped, typename Hash, typename TState>
    struct tuple_size<HashMapCellWithSavedHash<Key, TMapped, Hash, TState>> : std::integral_constant<size_t, 2> { };

    template <typename Key, typename TMapped, typename Hash, typename TState>
    struct tuple_element<0, HashMapCellWithSavedHash<Key, TMapped, Hash, TState>> { using type = Key; };

    template <typename Key, typename TMapped, typename Hash, typename TState>
    struct tuple_element<1, HashMapCellWithSavedHash<Key, TMapped, Hash, TState>> { using type = TMapped; };
}


template <
    typename Key,
    typename Mapped,
    typename Hash = DefaultHash<Key>,
    typename Grower = HashTableGrowerWithPrecalculation<>,
    typename Allocator = HashTableAllocator>
using HashMap = HashMapTable<Key, HashMapCell<Key, Mapped, Hash>, Hash, Grower, Allocator>;


template <
    typename Key,
    typename Mapped,
    typename Hash = DefaultHash<Key>,
    typename Grower = HashTableGrowerWithPrecalculation<>,
    typename Allocator = HashTableAllocator>
using HashMapWithSavedHash = HashMapTable<Key, HashMapCellWithSavedHash<Key, Mapped, Hash>, Hash, Grower, Allocator>;

template <typename Key, typename Mapped, typename Hash,
    size_t initial_size_degree>
using HashMapWithStackMemory = HashMapTable<
    Key,
    HashMapCellWithSavedHash<Key, Mapped, Hash>,
    Hash,
    HashTableGrower<initial_size_degree>,
    HashTableAllocatorWithStackMemory<
        (1ULL << initial_size_degree)
        * sizeof(HashMapCellWithSavedHash<Key, Mapped, Hash>)>>;
