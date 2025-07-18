#pragma once

#include <base/types.h>
#include <Parsers/IASTHash.h>
#include <Parsers/IAST_fwd.h>
#include <Parsers/IdentifierQuotingStyle.h>
#include <Parsers/LiteralEscapingStyle.h>
#include <Common/Exception.h>
#include <Common/TypePromotion.h>

#include <set>


class SipHash;


namespace DB
{

namespace ErrorCodes
{
    extern const int LOGICAL_ERROR;
}

using IdentifierNameSet = std::set<String>;

class WriteBuffer;
using Strings = std::vector<String>;

/** Element of the syntax tree (hereinafter - directed acyclic graph with elements of semantics)
  */
class IAST : public std::enable_shared_from_this<IAST>, public TypePromotion<IAST>
{
public:
    ASTs children;

    virtual ~IAST();
    IAST() = default;
    IAST(const IAST &) = default;
    IAST & operator=(const IAST &) = default;

    /** Get the canonical name of the column if the element is a column */
    String getColumnName() const;

    /** Same as the above but ensure no alias names are used. This is for index analysis */
    String getColumnNameWithoutAlias() const;

    virtual void appendColumnName(WriteBuffer &) const
    {
        throw Exception(ErrorCodes::LOGICAL_ERROR, "Trying to get name of not a column: {}", getID());
    }

    virtual void appendColumnNameWithoutAlias(WriteBuffer &) const
    {
        throw Exception(ErrorCodes::LOGICAL_ERROR, "Trying to get name of not a column: {}", getID());
    }

    /** Get the alias, if any, or the canonical name of the column, if it is not. */
    virtual String getAliasOrColumnName() const { return getColumnName(); }

    /** Get the alias, if any, or an empty string if it does not exist, or if the element does not support aliases. */
    virtual String tryGetAlias() const { return String(); }

    /** Set the alias. */
    virtual void setAlias(const String & /*to*/)
    {
        throw Exception(ErrorCodes::LOGICAL_ERROR, "Can't set alias of {} of {}", getColumnName(), getID());
    }

    /** Get the text that identifies this element. */
    virtual String getID(char delimiter = '_') const = 0; /// NOLINT

    ASTPtr ptr() { return shared_from_this(); }

    /** Get a deep copy of the tree. Cloned object must have the same range. */
    virtual ASTPtr clone() const = 0;

    /** Get hash code, identifying this element and its subtree.
     *  Hashing by default ignores aliases (e.g. identifier aliases, function aliases, literal aliases) which is
     *  useful for common subexpression elimination. Set 'ignore_aliases = false' if you don't want that behavior.
      */
    IASTHash getTreeHash(bool ignore_aliases) const;
    void updateTreeHash(SipHash & hash_state, bool ignore_aliases) const;
    virtual void updateTreeHashImpl(SipHash & hash_state, bool ignore_aliases) const;

    void dumpTree(WriteBuffer & ostr, size_t indent = 0) const;
    std::string dumpTree(size_t indent = 0) const;

    /** Check the depth of the tree.
      * If max_depth is specified and the depth is greater - throw an exception.
      * Returns the depth of the tree.
      */
    size_t checkDepth(size_t max_depth) const
    {
        return checkDepthImpl(max_depth);
    }

    /** Get total number of tree elements
     */
    size_t size() const;

    /** Same for the total number of tree elements.
      */
    size_t checkSize(size_t max_size) const;

    /** Get `set` from the names of the identifiers
     */
    virtual void collectIdentifierNames(IdentifierNameSet & set) const
    {
        for (const auto & child : children)
            child->collectIdentifierNames(set);
    }

    template <typename T>
    void set(T * & field, const ASTPtr & child)
    {
        if (!child)
            return;

        T * cast = dynamic_cast<T *>(child.get());
        if (!cast)
            throw Exception(ErrorCodes::LOGICAL_ERROR, "Could not cast AST subtree");

        children.push_back(child);
        field = cast;
    }

    template <typename T>
    void replace(T * & field, const ASTPtr & child)
    {
        if (!child)
            throw Exception(ErrorCodes::LOGICAL_ERROR, "Trying to replace AST subtree with nullptr");

        T * cast = dynamic_cast<T *>(child.get());
        if (!cast)
            throw Exception(ErrorCodes::LOGICAL_ERROR, "Could not cast AST subtree");

        for (ASTPtr & current_child : children)
        {
            if (current_child.get() == field)
            {
                current_child = child;
                field = cast;
                return;
            }
        }

        throw Exception(ErrorCodes::LOGICAL_ERROR, "AST subtree not found in children");
    }

    template <typename T>
    void setOrReplace(T * & field, const ASTPtr & child)
    {
        if (field)
            replace(field, child);
        else
            set(field, child);
    }

    template <typename T>
    void reset(T * & field)
    {
        if (field == nullptr)
            return;

        auto * child = children.begin();
        while (child != children.end())
        {
            if (child->get() == field)
                break;

            child++;
        }

        if (child == children.end())
            throw Exception(ErrorCodes::LOGICAL_ERROR, "AST subtree not found in children");

        children.erase(child);
        field = nullptr;
    }

    /// After changing one of `children` elements, update the corresponding member pointer if needed.
    void updatePointerToChild(void * old_ptr, void * new_ptr)
    {
        forEachPointerToChild([old_ptr, new_ptr](void ** ptr) mutable
        {
            if (*ptr == old_ptr)
                *ptr = new_ptr;
        });
    }

    /// Convert to a string.

    /// Format settings.
    struct FormatSettings
    {
        bool one_line;
        IdentifierQuotingRule identifier_quoting_rule;
        IdentifierQuotingStyle identifier_quoting_style;
        bool show_secrets; /// Show secret parts of the AST (e.g. passwords, encryption keys).
        char nl_or_ws; /// Newline or whitespace.
        LiteralEscapingStyle literal_escaping_style;
        bool print_pretty_type_names;
        bool enforce_strict_identifier_format;

        explicit FormatSettings(
            bool one_line_,
            IdentifierQuotingRule identifier_quoting_rule_ = IdentifierQuotingRule::WhenNecessary,
            IdentifierQuotingStyle identifier_quoting_style_ = IdentifierQuotingStyle::Backticks,
            bool show_secrets_ = true,
            LiteralEscapingStyle literal_escaping_style_ = LiteralEscapingStyle::Regular,
            bool print_pretty_type_names_ = false,
            bool enforce_strict_identifier_format_ = false)
            : one_line(one_line_)
            , identifier_quoting_rule(identifier_quoting_rule_)
            , identifier_quoting_style(identifier_quoting_style_)
            , show_secrets(show_secrets_)
            , nl_or_ws(one_line ? ' ' : '\n')
            , literal_escaping_style(literal_escaping_style_)
            , print_pretty_type_names(print_pretty_type_names_)
            , enforce_strict_identifier_format(enforce_strict_identifier_format_)
        {
        }

        void writeIdentifier(WriteBuffer & ostr, const String & name, bool ambiguous) const;
        void checkIdentifier(const String & name) const;
    };

    /// State. For example, a set of nodes can be remembered, which we already walk through.
    struct FormatState
    {
        /** The SELECT query in which the alias was found; identifier of a node with such an alias.
          * It is necessary that when the node has met again, output only the alias.
          */
        std::set<std::tuple<
            const IAST * /* SELECT query node */,
            std::string /* alias */,
            IASTHash /* printed content */>> printed_asts_with_alias;
    };

    /// The state that is copied when each node is formatted. For example, nesting level.
    struct FormatStateStacked
    {
        UInt16 indent = 0;
        bool need_parens = false;
        bool expression_list_always_start_on_new_line = false;  /// Line feed and indent before expression list even if it's of single element.
        bool expression_list_prepend_whitespace = false; /// Prepend whitespace (if it is required)
        bool surround_each_list_element_with_parens = false;
        bool ignore_printed_asts_with_alias = false; /// Ignore FormatState::printed_asts_with_alias
        bool allow_operators = true; /// Format some functions, such as "plus", "in", etc. as operators.
        size_t list_element_index = 0;
        std::string create_engine_name;
        const IAST * current_select = nullptr;
    };

    void format(WriteBuffer & ostr, const FormatSettings & settings) const
    {
        FormatState state;
        formatImpl(ostr, settings, state, FormatStateStacked());
    }

    void format(WriteBuffer & ostr, const FormatSettings & settings, FormatState & state, FormatStateStacked frame) const
    {
        formatImpl(ostr, settings, state, std::move(frame));
    }

    /// TODO: Move more logic into this class (see https://github.com/ClickHouse/ClickHouse/pull/45649).
    struct FormattingBuffer
    {
        WriteBuffer & ostr;
        const FormatSettings & settings;
        FormatState & state;
        FormatStateStacked frame;
    };

    void format(FormattingBuffer out) const
    {
        formatImpl(out.ostr, out.settings, out.state, out.frame);
    }

    /// Secrets are displayed regarding show_secrets, then SensitiveDataMasker is applied.
    /// You can use Interpreters/formatWithPossiblyHidingSecrets.h for convenience.
    String formatWithPossiblyHidingSensitiveData(
        size_t max_length,
        bool one_line,
        bool show_secrets,
        bool print_pretty_type_names,
        IdentifierQuotingRule identifier_quoting_rule,
        IdentifierQuotingStyle identifier_quoting_style) const;

    /** formatForLogging and formatForErrorMessage always hide secrets. This inconsistent
      * behaviour is due to the fact such functions are called from Client which knows nothing about
      * access rights and settings. Moreover, the only use case for displaying secrets are backups,
      * and backup tools use only direct input and ignore logs and error messages.
      */
    String formatForLogging(size_t max_length = 0) const;
    String formatForErrorMessage() const;
    String formatWithSecretsOneLine() const;
    String formatWithSecretsMultiLine() const;

    virtual bool hasSecretParts() const { return childrenHaveSecretParts(); }

    void cloneChildren();

    enum class QueryKind : uint8_t
    {
        None = 0,
        Select,
        Insert,
        Delete,
        Update,
        Create,
        Drop,
        Undrop,
        Rename,
        Optimize,
        Check,
        Alter,
        Grant,
        Revoke,
        Move,
        System,
        Set,
        Use,
        Show,
        Exists,
        Describe,
        Explain,
        Backup,
        Restore,
        KillQuery,
        ExternalDDL,
        Begin,
        Commit,
        Rollback,
        SetTransactionSnapshot,
        AsyncInsertFlush,
        ParallelWithQuery,
    };

    /// Return QueryKind of this AST query.
    virtual QueryKind getQueryKind() const { return QueryKind::None; }

protected:
    virtual void formatImpl(WriteBuffer & ostr, const FormatSettings & settings, FormatState & state, FormatStateStacked frame) const
    {
        formatImpl(FormattingBuffer{ostr, settings, state, std::move(frame)});
    }

    virtual void formatImpl(FormattingBuffer /*out*/) const
    {
        throw Exception(ErrorCodes::LOGICAL_ERROR, "Unknown element in AST: {}", getID());
    }

    bool childrenHaveSecretParts() const;

    /// Some AST classes have naked pointers to children elements as members.
    /// This method allows to iterate over them.
    virtual void forEachPointerToChild(std::function<void(void**)>) {}

private:
    size_t checkDepthImpl(size_t max_depth) const;

    /** Forward linked list of ASTPtr to delete.
      * Used in IAST destructor to avoid possible stack overflow.
      */
    ASTPtr next_to_delete = nullptr;
    ASTPtr * next_to_delete_list_head = nullptr;
};

}
