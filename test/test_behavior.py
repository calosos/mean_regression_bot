"""Behavioral regressions: current EA functions + deterministic MT5 mocks."""
import unittest

from test.harness import execute_cpp, scenario


class BehaviorTests(unittest.TestCase):
    def check_scenario(self, name, functions, **kwargs):
        output = execute_cpp(scenario(name, functions, **kwargs))
        self.assertIn("PASS:", output)

    def test_risk_volume_targets_and_cooldown(self):
        """12,570 sized trades, 86,400 cooldown times and strict signal boundaries."""
        self.check_scenario("risk", [
            "Budget", "Price", "SamePrice", "BarOf", "Target", "Risk", "Levels",
            "Size", "SignalSide", "ATRAllowed", "HitTarget", "Cooldown",
        ])

    def test_retries_cleanup_and_mixed_netting_protection(self):
        """60,000 ticks: retry pacing, no duplicates, recovery and foreign protection."""
        self.check_scenario("management", [
            "ManagementRetryIndex", "ManagementRequestAllowed", "RememberManagementResult",
            "PruneManagementRetries", "SyncTP", "CloseStep",
        ], structures=["ManagementRetry"], declarations=[
            "MANAGEMENT_RETRY_SECONDS", "g_management_retries", "g_request_cycle", "g_market_retry_after",
        ])

    def test_exit_reconciliation_and_delayed_identity(self):
        """E2 + two same-second exits: 24 permutations and 15 incomplete subsets."""
        self.check_scenario("exit_reporting", [
            "TrackId", "Tracked", "InspectIdeaHistory", "ReportHasId", "ReportAddId",
            "QueueExitReport", "ReportOrderVolume", "ReconcileExitReport",
            "RemoveExitReport", "FlushExitReports",
        ], structures=["ExitReport"], declarations=["g_exit_reports"])

    def test_signal_modes_and_no_late_entries(self):
        """Actual OnTick: valid/invalid, initialization, pauses, missing data and both modes."""
        self.check_scenario("signal_modes", [
            "BarOf", "SignalSide", "TakeClosedBarOpportunity", "ClosedSignalSide",
            "EvaluateClosedBarSignal", "OnTick",
        ])

    def test_signal_trace_fields_and_pause_age(self):
        """Actual formatter: coherent OHLC/indicators, quote separation and elapsed time."""
        self.check_scenario("signal_trace", ["SignalLog"])


if __name__ == "__main__":
    unittest.main()
