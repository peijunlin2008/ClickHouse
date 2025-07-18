#include <Common/quoteString.h>
#include <Common/FieldVisitorToString.h>
#include <IO/Operators.h>
#include <Parsers/ASTAlterNamedCollectionQuery.h>
#include <Parsers/formatSettingName.h>

namespace DB
{

ASTPtr ASTAlterNamedCollectionQuery::clone() const
{
    return std::make_shared<ASTAlterNamedCollectionQuery>(*this);
}

void ASTAlterNamedCollectionQuery::formatImpl(WriteBuffer & ostr, const IAST::FormatSettings & settings, IAST::FormatState &, IAST::FormatStateStacked) const
{
    ostr << "ALTER NAMED COLLECTION ";
    if (if_exists)
        ostr << "IF EXISTS ";
    ostr << backQuoteIfNeed(collection_name);
    formatOnCluster(ostr, settings);
    if (!changes.empty())
    {
        ostr << " SET ";
        bool first = true;
        for (const auto & change : changes)
        {
            if (!first)
                ostr << ", ";
            else
                first = false;

            formatSettingName(change.name, ostr);
            if (settings.show_secrets)
                ostr << " = " << applyVisitor(FieldVisitorToString(), change.value);
            else
                ostr << " = '[HIDDEN]'";
            auto override_value = overridability.find(change.name);
            if (override_value != overridability.end())
                ostr << " " << (override_value->second ? "" : "NOT ") << "OVERRIDABLE";
        }
    }
    if (!delete_keys.empty())
    {
        ostr << " DELETE ";
        bool first = true;
        for (const auto & key : delete_keys)
        {
            if (!first)
                ostr << ", ";
            else
                first = false;

            formatSettingName(key, ostr);
        }
    }
}

}
