#!/usr/bin/env bash
# Brave macOS Policy Manager
# Applies Brave Browser enterprise policies on macOS using Managed Preferences.
#
# Default mode:
#   Applies the full recommended lockdown/debloat policy set.
#
# Interactive mode:
#   Lets the user choose policy groups to apply.
#
# Restore mode:
#   Removes only the policy keys managed by this script.
#
# Target plist:
#   /Library/Managed Preferences/com.brave.Browser.plist
#
# Check result:
#   brave://policy

set -euo pipefail

PLIST="/Library/Managed Preferences/com.brave.Browser.plist"
BUNDLE_NAME="Brave Browser"
SCRIPT_NAME="$(basename "$0")"

DRY_RUN=0
RESTART_BRAVE=1

usage() {
  cat <<EOF
Brave macOS Policy Manager

Usage:
  ./${SCRIPT_NAME}                 Apply default full policy set
  ./${SCRIPT_NAME} --default       Apply default full policy set
  ./${SCRIPT_NAME} --interactive   Choose policy groups interactively
  ./${SCRIPT_NAME} --restore       Remove all policies managed by this script
  ./${SCRIPT_NAME} --dry-run       Preview actions without changing plist
  ./${SCRIPT_NAME} --no-restart    Do not restart Brave after applying
  ./${SCRIPT_NAME} --help          Show help

Examples:
  ./${SCRIPT_NAME}
  ./${SCRIPT_NAME} --interactive
  ./${SCRIPT_NAME} --restore
  ./${SCRIPT_NAME} --interactive --dry-run

After applying:
  Open brave://policy and click "Reload policies".

Note:
  Brave may show "Managed by your organization". This is expected when
  enterprise policies are applied locally.
EOF
}

log() {
  printf '%s\n' "$*"
}

require_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Error: This script is intended for macOS only." >&2
    exit 1
  fi
}

ensure_plist() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[dry-run] Would create: $PLIST"
    return
  fi

  sudo mkdir -p "$(dirname "$PLIST")"
  sudo chown root:wheel "$(dirname "$PLIST")"
  sudo chmod 755 "$(dirname "$PLIST")"

  if [[ ! -f "$PLIST" ]]; then
    sudo tee "$PLIST" >/dev/null <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
EOF
  fi

  sudo chmod 644 "$PLIST"
  sudo chown root:wheel "$PLIST"
}

backup_plist() {
  if [[ -f "$PLIST" && "$DRY_RUN" -eq 0 ]]; then
    local backup="${PLIST}.backup.$(date +%Y%m%d-%H%M%S)"
    sudo cp "$PLIST" "$backup"
    log "Backup created: $backup"
  elif [[ "$DRY_RUN" -eq 1 ]]; then
    log "[dry-run] Would back up plist if it exists."
  fi
}

plist_set() {
  local key="$1"
  local type="$2"
  local value="$3"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[dry-run] Set $key ($type) = $value"
    return
  fi

  case "$type" in
    bool)
      if [[ "$value" != "true" && "$value" != "false" ]]; then
        echo "Invalid bool value for $key: $value" >&2
        exit 1
      fi
      sudo /usr/libexec/PlistBuddy -c "Add :$key bool $value" "$PLIST" 2>/dev/null || \
      sudo /usr/libexec/PlistBuddy -c "Set :$key $value" "$PLIST"
      ;;
    integer)
      sudo /usr/libexec/PlistBuddy -c "Add :$key integer $value" "$PLIST" 2>/dev/null || \
      sudo /usr/libexec/PlistBuddy -c "Set :$key $value" "$PLIST"
      ;;
    string)
      sudo /usr/libexec/PlistBuddy -c "Add :$key string $value" "$PLIST" 2>/dev/null || \
      sudo /usr/libexec/PlistBuddy -c "Set :$key $value" "$PLIST"
      ;;
    *)
      echo "Unsupported plist type: $type" >&2
      exit 1
      ;;
  esac
}

plist_delete() {
  local key="$1"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[dry-run] Delete $key"
    return
  fi
  sudo /usr/libexec/PlistBuddy -c "Delete :$key" "$PLIST" 2>/dev/null || true
}

finish() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[dry-run] No changes were written."
    return
  fi

  sudo chmod 644 "$PLIST"
  sudo chown root:wheel "$PLIST"
  killall cfprefsd 2>/dev/null || true

  if [[ "$RESTART_BRAVE" -eq 1 ]]; then
    killall "$BUNDLE_NAME" 2>/dev/null || true
    open -a "$BUNDLE_NAME" 2>/dev/null || true
  fi

  log ""
  log "Done."
  log "Open brave://policy and click \"Reload policies\"."
}

apply_brave_features() {
  log "Applying: Brave feature debloat"
  plist_set "BraveAIChatEnabled" "bool" "false"
  plist_set "BraveRewardsDisabled" "bool" "true"
  plist_set "BraveWalletDisabled" "bool" "true"
  plist_set "BraveVPNDisabled" "bool" "true"
  plist_set "BraveNewsDisabled" "bool" "true"
  plist_set "BraveTalkDisabled" "bool" "true"
  plist_set "TorDisabled" "bool" "true"
}

apply_telemetry() {
  log "Applying: telemetry and reporting shutdown"
  plist_set "BraveP3AEnabled" "bool" "false"
  plist_set "BraveStatsPingEnabled" "bool" "false"
  plist_set "MetricsReportingEnabled" "bool" "false"
  plist_set "BraveWebDiscoveryEnabled" "bool" "false"
  plist_set "UrlKeyedAnonymizedDataCollectionEnabled" "bool" "false"
  plist_set "UserFeedbackAllowed" "bool" "false"
  plist_set "WebRtcEventLogCollectionAllowed" "bool" "false"
}

apply_shields_privacy() {
  log "Applying: Brave Shields and privacy protections"
  plist_set "DefaultBraveAdblockSetting" "integer" "2"
  plist_set "DefaultBraveFingerprintingV2Setting" "integer" "3"
  plist_set "DefaultBraveReferrersSetting" "integer" "2"
  plist_set "BraveTrackingQueryParametersFilteringEnabled" "bool" "true"
  plist_set "BraveDeAmpEnabled" "bool" "true"
  plist_set "BraveDebouncingEnabled" "bool" "true"
  plist_set "BraveGlobalPrivacyControlEnabled" "bool" "true"
  plist_set "BraveReduceLanguageEnabled" "bool" "true"
}

apply_passwords_autofill_payments() {
  log "Applying: password manager, autofill, and payments shutdown"
  plist_set "PasswordManagerEnabled" "bool" "false"
  plist_set "PasswordLeakDetectionEnabled" "bool" "false"
  plist_set "AutofillAddressEnabled" "bool" "false"
  plist_set "AutofillCreditCardEnabled" "bool" "false"
  plist_set "PaymentMethodQueryEnabled" "bool" "false"
  plist_set "ImportSavedPasswords" "bool" "false"
  plist_set "ImportAutofillFormData" "bool" "false"
  plist_set "ImportHistory" "bool" "false"
}

apply_search_language() {
  log "Applying: search suggestions, spelling, error pages, and translation shutdown"
  plist_set "SearchSuggestEnabled" "bool" "false"
  plist_set "SpellCheckServiceEnabled" "bool" "false"
  plist_set "AlternateErrorPagesEnabled" "bool" "false"
  plist_set "TranslateEnabled" "bool" "false"
}

apply_safe_browsing_standard() {
  log "Applying: Safe Browsing standard protection with extra reporting disabled"
  plist_set "SafeBrowsingProtectionLevel" "integer" "1"
  plist_set "SafeBrowsingExtendedReportingEnabled" "bool" "false"
  plist_set "SafeBrowsingDeepScanningEnabled" "bool" "false"
  plist_set "SafeBrowsingSurveysEnabled" "bool" "false"
}

apply_network_dns() {
  log "Applying: DNS and network behavior"
  plist_set "DnsOverHttpsMode" "string" "automatic"
  plist_set "NetworkPredictionOptions" "integer" "2"
  plist_set "QuicAllowed" "bool" "true"
}

apply_performance_ui() {
  log "Applying: performance and UI cleanup"
  plist_set "HighEfficiencyModeEnabled" "bool" "true"
  plist_set "BatterySaverModeAvailability" "integer" "2"
  plist_set "HardwareAccelerationModeEnabled" "bool" "true"
  plist_set "DiskCacheSize" "integer" "262144000"
  plist_set "BrowserLabsEnabled" "bool" "false"
  plist_set "LiveCaptionEnabled" "bool" "false"
  plist_set "AccessibilityImageLabelsEnabled" "bool" "false"
  plist_set "NTPCustomBackgroundEnabled" "bool" "false"
  plist_set "DefaultBrowserSettingEnabled" "bool" "false"
}

apply_genai() {
  log "Applying: Chromium/Chrome GenAI shutdown"
  plist_set "CreateThemesSettings" "integer" "2"
  plist_set "DevToolsGenAiSettings" "integer" "2"
  plist_set "HelpMeWriteSettings" "integer" "2"
  plist_set "HistorySearchSettings" "integer" "2"
}

apply_variations() {
  log "Applying: Chrome Variations restriction"
  plist_set "ChromeVariations" "integer" "2"
}

apply_default() {
  log "Applying default full policy set..."
  apply_brave_features
  apply_telemetry
  apply_shields_privacy
  apply_passwords_autofill_payments
  apply_search_language
  apply_safe_browsing_standard
  apply_network_dns
  apply_performance_ui
  apply_genai
  apply_variations
}

print_interactive_menu() {
  cat <<'EOF'

Choose policy groups to apply.
Enter numbers separated by spaces, or type "all".

  1) Brave feature debloat
     Disable Leo AI, Rewards, Wallet, VPN, News, Talk, Tor.

  2) Telemetry and reporting shutdown
     Disable P3A, usage ping, metrics, Web Discovery, URL keyed data, feedback.

  3) Brave Shields and privacy protections
     Enable adblock, fingerprinting protection, referrer protection, De-AMP,
     debouncing, GPC, language fingerprinting reduction.

  4) Password manager, autofill, and payments shutdown
     Disable Brave password manager, leak detection, address autofill,
     credit-card autofill, payment method queries, and related imports.

  5) Search suggestions, spelling, error pages, and translation shutdown
     Disable search suggestions, cloud spellcheck, alternate error pages,
     and translation.

  6) Safe Browsing standard mode
     Keep Standard protection and disable extended reporting, deep scanning,
     and surveys.

  7) DNS and network behavior
     Set Secure DNS mode to automatic, disable network prediction, allow QUIC.

  8) Performance and UI cleanup
     Enable memory saver and hardware acceleration; disable Browser Labs,
     Live Caption, image labels, NTP custom background, default browser prompt.

  9) Chromium/Chrome GenAI shutdown
     Disable Create Themes, DevTools GenAI, Help Me Write, AI History Search.

 10) Chrome Variations restriction
     Restrict Chrome Variations / field trials.

  0) Cancel

EOF
}

apply_interactive() {
  print_interactive_menu
  read -r -p "Selection: " selection

  if [[ "$selection" == "0" ]]; then
    log "Cancelled."
    exit 0
  fi

  if [[ "$selection" == "all" || "$selection" == "ALL" ]]; then
    apply_default
    return
  fi

  for item in $selection; do
    case "$item" in
      1) apply_brave_features ;;
      2) apply_telemetry ;;
      3) apply_shields_privacy ;;
      4) apply_passwords_autofill_payments ;;
      5) apply_search_language ;;
      6) apply_safe_browsing_standard ;;
      7) apply_network_dns ;;
      8) apply_performance_ui ;;
      9) apply_genai ;;
      10) apply_variations ;;
      *) log "Skipping unknown selection: $item" ;;
    esac
  done
}

managed_keys() {
  cat <<'EOF'
AccessibilityImageLabelsEnabled
AlternateErrorPagesEnabled
AutofillAddressEnabled
AutofillCreditCardEnabled
BatterySaverModeAvailability
BraveAIChatEnabled
BraveDeAmpEnabled
BraveDebouncingEnabled
BraveGlobalPrivacyControlEnabled
BraveNewsDisabled
BraveP3AEnabled
BraveReduceLanguageEnabled
BraveRewardsDisabled
BraveStatsPingEnabled
BraveTalkDisabled
BraveTrackingQueryParametersFilteringEnabled
BraveVPNDisabled
BraveWalletDisabled
BraveWebDiscoveryEnabled
BrowserLabsEnabled
ChromeVariations
CreateThemesSettings
DefaultBraveAdblockSetting
DefaultBraveFingerprintingV2Setting
DefaultBraveReferrersSetting
DefaultBrowserSettingEnabled
DevToolsGenAiSettings
DiskCacheSize
DnsOverHttpsMode
HardwareAccelerationModeEnabled
HelpMeWriteSettings
HighEfficiencyModeEnabled
HistorySearchSettings
ImportAutofillFormData
ImportHistory
ImportSavedPasswords
LiveCaptionEnabled
MetricsReportingEnabled
NTPCustomBackgroundEnabled
NetworkPredictionOptions
PasswordLeakDetectionEnabled
PasswordManagerEnabled
PaymentMethodQueryEnabled
QuicAllowed
SafeBrowsingDeepScanningEnabled
SafeBrowsingExtendedReportingEnabled
SafeBrowsingProtectionLevel
SafeBrowsingSurveysEnabled
SearchSuggestEnabled
SpellCheckServiceEnabled
TorDisabled
TranslateEnabled
UrlKeyedAnonymizedDataCollectionEnabled
UserFeedbackAllowed
WebRtcEventLogCollectionAllowed
EOF
}

restore_policies() {
  log "Removing policies managed by this script..."
  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    plist_delete "$key"
  done < <(managed_keys)
}

MODE="default"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --default)
      MODE="default"
      shift
      ;;
    --interactive|-i)
      MODE="interactive"
      shift
      ;;
    --restore)
      MODE="restore"
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --no-restart)
      RESTART_BRAVE=0
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

require_macos
ensure_plist
backup_plist

case "$MODE" in
  default)
    apply_default
    ;;
  interactive)
    apply_interactive
    ;;
  restore)
    restore_policies
    ;;
  *)
    echo "Unknown mode: $MODE" >&2
    exit 1
    ;;
esac

finish
