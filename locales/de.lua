Locales = Locales or {}

Locales['de'] = {
    cmd_usage_getstatic = 'Fehler: Nutzung /getstatic [Dynamische ID]',
    cmd_usage_getdynamic = 'Fehler: Nutzung /getdynamic [Statische ID]',
    static_id_result = 'Statische ID von %d: %d',
    static_id_not_found = 'Keine statische ID zu %d gefunden.',
    dynamic_id_result = 'Dynamische ID zu %d: %d',
    dynamic_id_not_found = 'Keine dynamische ID zu %d (Spieler offline?).',
    help_header = 'StaticID Befehle:',
    help_getstatic = '/getstatic (/gs) [Dynamische ID] -> Statische ID anzeigen',
    help_getdynamic = '/getdynamic (/gd) [Statische ID] -> Dynamische ID anzeigen',
    cache_refresh_start = 'Starte Cache-Refresh...',
    cache_refresh_done = 'Cache-Refresh abgeschlossen (%d Einträge).',
    cache_prune_done = 'Cache bereinigt (%d entfernt).',
    preload_player = 'Preload für Spieler %s (%s => %s)',
    invalid_param_dyn = 'Ungültige dynamische ID',
    invalid_param_static = 'Ungültige statische ID',
    sql_error = 'SQL Fehler: %s',
    param_error = 'Parameterfehler: %s',
    persist_saved = 'Persistenter Cache gespeichert (%s)',
    persist_loaded = 'Persistenter Cache geladen (%s)',
    persist_cleared = 'Persistenter Cache gelöscht (%s)',
    persist_cmd_save = 'Cache wurde gespeichert.',
    persist_cmd_clear = 'Persistente Datei gelöscht.',
    persist_cmd_disabled = 'Persistente Speicherung ist deaktiviert.'
    ,whois_usage = '/whois [DynamischeID|StatischeID]',
    whois_dyn = 'WHOIS Dyn %d -> Static %d | Identifier %s | %s',
    whois_static_full = 'WHOIS Static %d -> Dyn %d | Identifier %s | %s',
    whois_static_no_dyn = 'WHOIS Static %d -> Dyn n/a | Identifier %s | %s',
    whois_not_found = 'WHOIS: Keine Daten zu %d',
    checksum_mismatch = 'Checksumme stimmt nicht, Datei ignoriert.'
    ,dynamic_checksum_mismatch = 'Dynamische Checksumme stimmt nicht, dynamische Sektion verworfen.'
    ,resolve_usage = '/resolve <id1,id2,...>'
    ,resolve_prefix_dyn = 'Dyn %d -> Static %d (%s)'
    ,resolve_prefix_static = 'Static %d -> Dyn %d (%s)'
    ,resolve_unknown = '%s ?'
    ,migration_start = 'Starte einmalige Migration users -> static_ids'
    ,migration_skip = 'Migration übersprungen (Tabelle nicht leer)'
    ,migration_done = 'Migration fertig (%d Insert-Versuche, Duplikate ignoriert)'
    ,migration_abort = 'Migration abgebrochen: keine User-Daten'
    ,whois_not_numeric = '/whois erwartet eine numerische ID'
    ,info_summary = 'StaticID Info -> Framework: %s | SeparateTable: %s | Persistence: %s'
    ,resolve_result_joiner = ' | '
    ,standalone_identifier_note = 'Standalone Modus: nutze rohen license (oder ersten) Identifier; separate Tabelle empfohlen.'
    ,standalone_forced_table = 'Standalone: separate static_ids Tabelle erzwungen AKTIV.'
    ,standalone_warn_header = 'Standalone StaticID Status:'
    ,standalone_warn_table_on = 'Separate Tabelle: AKTIV'
    ,standalone_warn_table_off = 'Separate Tabelle: INAKTIV (sollte aktiviert sein!)'
    ,standalone_warn_ident_order = 'Identifier Reihenfolge: %s'
    ,conflict_scan_start = 'Konflikt-Scan gestartet (bis zu %d Zeilen)'
    ,conflict_scan_done = 'Konflikt-Scan fertig (%d Konflikte, %d geprüft)'
    ,conflict_detected = 'Konflikt: Identifier %s unterschiedliche Static IDs (Cache=%s DB=%s)'
    ,conflict_cmd_header = 'Konflikt-Erkennung Zusammenfassung: gesamt=%d gespeichert=%d'
    ,conflict_none = 'Keine Konflikte aufgezeichnet.'
}
