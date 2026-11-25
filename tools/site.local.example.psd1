@{
    # Copy this file to tools\site.local.psd1 and fill in the real values.
    # site.local.psd1 is gitignored: the real server and database names must
    # never appear in a tracked file. See CLAUDE.md "Never publish real site
    # identifiers".
    #
    # The date epoch is NOT set here. Its one source is the generated
    # docs\schema\site-profile.md (section "Epoch"), where it is proved.

    # SQL Server instance that hosts Horizon.
    Server   = 'ILSSERVER'

    # Horizon database name.
    Database = 'ILSDB'
}
