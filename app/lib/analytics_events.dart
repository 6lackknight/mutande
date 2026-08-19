/// Desktop product analytics event names (Mixpanel).
///
/// No mail content. Never put email/handle/token in props.
class AnalyticsEvent {
  AnalyticsEvent._();

  static const appOpen = 'desktop_app_open';

  static const signInClick = 'desktop_sign_in_click';
  static const signInSuccess = 'desktop_sign_in_success';
  static const signInFailure = 'desktop_sign_in_failure';

  static const createTeamClick = 'desktop_create_team_click';
  static const createTeamSuccess = 'desktop_create_team_success';
  static const createTeamFailure = 'desktop_create_team_failure';

  static const joinInviteClick = 'desktop_join_invite_click';
  static const joinInviteSuccess = 'desktop_join_invite_success';
  static const joinInviteFailure = 'desktop_join_invite_failure';

  static const connectHostPicked = 'desktop_connect_host_picked';
  static const connectMcpSuccess = 'desktop_connect_mcp_success';
  static const connectMcpFailure = 'desktop_connect_mcp_failure';
  static const connectSkillSuccess = 'desktop_connect_skill_success';
  static const connectSkillFailure = 'desktop_connect_skill_failure';
  static const connectComplete = 'desktop_connect_complete';

  static const pingCopy = 'desktop_handoff_copy';
  static const pingOpen = 'desktop_handoff_open';
  static const pingWaiting = 'desktop_handoff_waiting';
  static const pingSuccess = 'desktop_handoff_success';
  static const pingTimeout = 'desktop_handoff_timeout';

  static const homeReady = 'desktop_home_ready';
  static const tabSelect = 'desktop_tab_select';
  static const signOut = 'desktop_sign_out';

  static const updateRequired = 'desktop_update_required';
}
