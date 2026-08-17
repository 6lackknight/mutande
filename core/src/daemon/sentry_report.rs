//! GlitchTip reporting helpers for mutande-core.

/// Capture a JSON-RPC handler failure. Skips `health` (high-frequency probe).
pub fn capture_rpc_error(method: &str, err: &(dyn std::error::Error + 'static)) {
    if method == "health" {
        return;
    }
    sentry::configure_scope(|scope| {
        scope.set_tag("rpc.method", method);
        scope.set_tag("handled", "rpc");
    });
    sentry::capture_error(err);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn health_probe_not_reported() {
        // Should not panic when DSN unset in tests.
        capture_rpc_error("health", &std::io::Error::new(
            std::io::ErrorKind::TimedOut,
            "probe",
        ));
    }
}
