@{
    # Copy this file to tools\site.local.psd1 and fill in the real values.
    # site.local.psd1 is gitignored: the real server and database names must
    # never appear in a tracked file. See CLAUDE.md "Never publish real site
    # identifiers".

    # SQL Server instance that hosts Horizon.
    Server   = 'ILSSERVER'

    # Horizon database name.
    Database = 'ILSDB'

    # The day the integer date columns count from. Copy it from
    # docs\schema\site-profile.md (section "Epoch"); never assume it.
    Epoch    = '1970-01-01'
}
