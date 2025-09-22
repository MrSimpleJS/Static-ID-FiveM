Locales = Locales or {}

Locales['en'] = {
    cmd_usage_getstatic = 'Usage: /getstatic [Dynamic ID]',
    cmd_usage_getdynamic = 'Usage: /getdynamic [Static ID]',
    static_id_result = 'Static ID of %d: %d',
    static_id_not_found = 'No static ID for %d found.',
    dynamic_id_result = 'Dynamic ID for %d: %d',
    dynamic_id_not_found = 'No dynamic ID for %d (player offline?).',
    help_header = 'StaticID Commands:',
    help_getstatic = '/getstatic (/gs) [Dynamic ID] -> Show static ID',
    help_getdynamic = '/getdynamic (/gd) [Static ID] -> Show dynamic ID (if online)',
    cache_refresh_start = 'Starting cache refresh...',
    cache_refresh_done = 'Cache refresh done (%d entries).',
    cache_prune_done = 'Cache pruned (%d removed).',
    preload_player = 'Preload for player %s (%s => %s)',
    invalid_param_dyn = 'Invalid dynamic ID',
    invalid_param_static = 'Invalid static ID',
    sql_error = 'SQL Error: %s',
    param_error = 'Parameter error: %s',
    persist_saved = 'Persistent cache saved (%s)',
    persist_loaded = 'Persistent cache loaded (%s)',
    persist_loaded_verbose = 'Persistent cache loaded: file=%s | entries=%d | dyn=%d | %s',
    persist_cleared = 'Persistent cache removed (%s)',
    persist_cmd_save = 'Cache has been saved.',
    persist_cmd_clear = 'Persistent file removed.',
    persist_cmd_disabled = 'Persistent storage is disabled.'
    ,whois_usage = '/whois [DynamicID|StaticID]',
    whois_dyn = 'WHOIS Dyn %d -> Static %d | Identifier %s | %s',
    whois_static_full = 'WHOIS Static %d -> Dyn %d | Identifier %s | %s',
    whois_static_no_dyn = 'WHOIS Static %d -> Dyn n/a | Identifier %s | %s',
    whois_not_found = 'WHOIS: No data for %d',
    checksum_mismatch = 'Checksum mismatch, ignoring file.'
    ,dynamic_checksum_mismatch = 'Dynamic checksum mismatch, dynamic section dropped.'
    ,resolve_usage = '/resolve <id1,id2,...>'
    ,resolve_prefix_dyn = 'Dyn %d -> Static %d (%s)'
    ,resolve_prefix_static = 'Static %d -> Dyn %d (%s)'
    ,resolve_unknown = '%s ?'
    ,migration_start = 'Starting one-time migration users -> static_ids'
    ,migration_skip = 'Migration skipped (table not empty)'
    ,migration_done = 'Migration finished (%d insert attempts, duplicates ignored)'
    ,migration_abort = 'Migration aborted: no user rows'
    ,whois_not_numeric = '/whois expects a numeric ID'
    ,info_summary = 'StaticID Info -> Framework: %s | SeparateTable: %s | Persistence: %s'
    ,resolve_result_joiner = ' | '
    ,standalone_identifier_note = 'Standalone mode: using raw license (or first) identifier; ensure separate table recommended.'
    ,standalone_forced_table = 'Standalone: separate static_ids table forced ON.'
    ,standalone_warn_header = 'Standalone StaticID Status:'
    ,standalone_warn_table_on = 'Separate table: ENABLED'
    ,standalone_warn_table_off = 'Separate table: DISABLED (should be enabled!)'
    ,standalone_warn_ident_order = 'Identifier order: %s'
    ,conflict_scan_start = 'Conflict scan started (sampling up to %d rows)'
    ,conflict_scan_done = 'Conflict scan complete (%d conflicts, %d checked)'
    ,conflict_detected = 'Conflict: identifier %s has differing static IDs (cache=%s db=%s)'
    ,conflict_cmd_header = 'Conflict Detection Summary: total=%d stored=%d'
    ,conflict_none = 'No conflicts recorded.'
    ,assigned_new = 'Assigned new static ID: %s -> %d'
    ,reset_done = 'StaticID table & cache reset.'
    ,reset_fail = 'StaticID reset failed: %s'
}
