///|
pub async fn start(args : ArrayView[String]) -> Unit {
  let arr = args.to_array()
  if run_registered_cli_command(arr) {
    return
  }
  match arr[1:] {
    ["get_installed_skills", ..] | ["get-installed-skills", ..] =>
      check_usage_endpoint(arr, "/get_installed_skills")
    ["get_skill_backups", ..] | ["get-skill-backups", ..] =>
      check_usage_endpoint(arr, "/get_skill_backups")
    ["delete_skill_backup", ..] | ["delete-skill-backup", ..] =>
      check_json_post_endpoint(
        arr,
        skill_backup_id_path(arr, "/delete_skill_backup"),
        "Skills",
      )
    ["restore_skill_backup", ..] | ["restore-skill-backup", ..] =>
      check_json_post_endpoint(arr, skill_restore_backup_path(arr), "Skills")
    ["install_skill_unified", ..] | ["install-skill-unified", ..] =>
      check_json_post_endpoint(
        arr,
        skill_install_path(arr, "/install_skill_unified"),
        "Skills",
      )
    ["uninstall_skill_unified", ..] | ["uninstall-skill-unified", ..] =>
      check_json_post_endpoint(
        arr,
        skill_id_path(arr, "/uninstall_skill_unified"),
        "Skills",
      )
    ["toggle_skill_app", ..] | ["toggle-skill-app", ..] =>
      check_json_post_endpoint(arr, skill_toggle_app_path(arr), "Skills")
    ["scan_unmanaged_skills", ..] | ["scan-unmanaged-skills", ..] =>
      check_usage_endpoint(arr, "/scan_unmanaged_skills")
    ["import_skills_from_apps", ..] | ["import-skills-from-apps", ..] =>
      import_skills_from_apps(arr)
    ["discover_available_skills", ..] | ["discover-available-skills", ..] =>
      check_usage_endpoint(arr, "/discover_available_skills")
    ["check_skill_updates", ..] | ["check-skill-updates", ..] =>
      check_usage_endpoint(arr, "/check_skill_updates")
    ["update_skill", ..] | ["update-skill", ..] =>
      check_json_post_endpoint(
        arr,
        skill_id_path(arr, "/update_skill"),
        "Skills",
      )
    ["migrate_skill_storage", ..] | ["migrate-skill-storage", ..] =>
      migrate_skill_storage(arr)
    ["search_skills_sh", ..] | ["search-skills-sh", ..] =>
      check_usage_endpoint(arr, skill_search_path(arr))
    ["get_skills", ..] | ["get-skills", ..] =>
      check_usage_endpoint(arr, "/get_skills")
    ["get_skills_for_app", ..] | ["get-skills-for-app", ..] =>
      check_usage_endpoint(arr, skill_app_path(arr, "/get_skills_for_app"))
    ["install_skill", ..] | ["install-skill", ..] =>
      check_json_post_endpoint(
        arr,
        skill_install_path(arr, "/install_skill"),
        "Skills",
      )
    ["install_skill_for_app", ..] | ["install-skill-for-app", ..] =>
      check_json_post_endpoint(
        arr,
        skill_install_path(arr, "/install_skill_for_app"),
        "Skills",
      )
    ["uninstall_skill", ..] | ["uninstall-skill", ..] =>
      check_json_post_endpoint(
        arr,
        skill_id_path(arr, "/uninstall_skill"),
        "Skills",
      )
    ["uninstall_skill_for_app", ..] | ["uninstall-skill-for-app", ..] =>
      check_json_post_endpoint(
        arr,
        skill_id_path(arr, "/uninstall_skill_for_app"),
        "Skills",
      )
    ["get_skill_repos", ..] | ["get-skill-repos", ..] =>
      check_usage_endpoint(arr, "/get_skill_repos")
    ["add_skill_repo", ..] | ["add-skill-repo", ..] =>
      check_json_post_endpoint(arr, skill_repo_add_path(arr), "Skills")
    ["remove_skill_repo", ..] | ["remove-skill-repo", ..] =>
      check_json_post_endpoint(arr, skill_repo_remove_path(arr), "Skills")
    ["install_skills_from_zip", ..] | ["install-skills-from-zip", ..] =>
      check_json_post_endpoint(arr, skill_zip_install_path(arr), "Skills")
    ["get_app_config_path", ..] | ["get-app-config-path", ..] =>
      check_usage_endpoint(arr, "/get_app_config_path")
    ["open_app_config_folder", ..] | ["open-app-config-folder", ..] =>
      check_usage_endpoint(arr, "/open_app_config_folder")
    ["get_claude_common_config_snippet", ..]
    | ["get-claude-common-config-snippet", ..] =>
      check_usage_endpoint(arr, "/get_claude_common_config_snippet")
    ["set_claude_common_config_snippet", ..]
    | ["set-claude-common-config-snippet", ..] =>
      set_config_snippet(
        arr,
        "/set_claude_common_config_snippet",
        app_required=false,
      )
    ["get_common_config_snippet", ..] | ["get-common-config-snippet", ..] =>
      check_usage_endpoint(
        arr,
        config_app_path(arr, "/get_common_config_snippet"),
      )
    ["set_common_config_snippet", ..] | ["set-common-config-snippet", ..] =>
      set_config_snippet(arr, "/set_common_config_snippet", app_required=true)
    ["extract_common_config_snippet", ..]
    | ["extract-common-config-snippet", ..] =>
      check_usage_endpoint(arr, extract_common_config_snippet_path(arr))
    ["check_env_conflicts", ..] | ["check-env-conflicts", ..] =>
      check_usage_endpoint(arr, config_app_path(arr, "/check_env_conflicts"))
    ["delete_env_vars", ..] | ["delete-env-vars", ..] => delete_env_vars(arr)
    ["restore_env_backup", ..] | ["restore-env-backup", ..] =>
      restore_env_backup(arr)
    _ => print_help()
  }
}
