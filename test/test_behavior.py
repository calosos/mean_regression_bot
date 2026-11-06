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
            "Size", "Value", "SignalSide", "ATRAllowed", "HitTarget", "Cooldown",
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
            "QueueExitReport", "ReportOrderVolume", "DiagnosticOrderVolume", "ReconcileIdeaPnl",
            "ReconcileExitReport", "ResetExcursions", "UpdateExcursions", "ExitDiagnosticText",
            "RemoveExitReport", "FlushExitReports",
        ], structures=["ExcursionStats", "DiagnosticPosition", "ExitReport"], declarations=["g_exit_reports", "g_excursions"])

    def test_monetary_excursions_and_reconciliation(self):
        """Joint MFE/MAE, E2, partial/simultaneous closes, races and final EXIT."""
        self.check_scenario("excursions", [
            "ReportHasId", "ReportAddId", "QueueExitReport", "ReportOrderVolume",
            "DiagnosticOrderVolume", "ReconcileIdeaPnl", "ReconcileExitReport",
            "ResetExcursions", "UpdateExcursions", "ObserveIdeaExcursions",
            "ExitDiagnosticText", "RemoveExitReport", "FlushExitReports",
        ], structures=["ExcursionStats", "DiagnosticPosition", "ExitReport"],
           declarations=["g_exit_reports", "g_excursions"])

    def test_signal_modes_and_no_late_entries(self):
        """Actual OnTick: valid/invalid, initialization, pauses, missing data and both modes."""
        self.check_scenario("signal_modes", [
            "TargetInputs", "BarOf", "SignalSide", "TakeClosedBarOpportunity", "ClosedSignalSide",
            "ClearReentry", "Cooldown", "EvaluateClosedBarSignal", "ValidBBWInputs", "ConfirmReentryBBWP70", "ConfirmReentryBBW", "ReentryADXModeName", "ConfirmReentryADX", "ConfirmReentryMACD", "EvaluateReentrySignal", "EvaluateATRDeviationSignal", "WickSignalSide", "EvaluateWickSignal", "OnTick",
        ])

    def test_single_entry_execution_and_sma_target(self):
        """Actual entry/SL/TP functions with controlled fills, failures and restrictions."""
        self.check_scenario("single_entry", [
            "Budget", "Price", "SamePrice", "Target", "Risk", "Levels", "Size",
            "StopDistance", "HitTarget", "ValidSL", "ValidTP", "SyncTP", "SetInitialSL",
            "ATRAllowed", "OpenIdea",
        ])

    def test_strategy_initialization_and_selected_indicators(self):
        """Actual OnInit: fixed BB settings, ignored inputs and RSI/Stochastic validation."""
        self.check_scenario("initialization", ["Budget", "BarOf", "ReentryADXModeName", "OnInit"])

    def test_weekend_schedule_and_guard_lifecycle(self):
        """Actual session reader/guard/OnTick with synthetic broker sessions and times."""
        self.check_scenario("weekend", [
            "TargetInputs", "BarOf", "SignalSide", "TakeClosedBarOpportunity", "ClosedSignalSide", "ClearReentry", "Cooldown",
            "EvaluateClosedBarSignal", "ValidBBWInputs", "ConfirmReentryBBWP70", "ConfirmReentryBBW", "ReentryADXModeName", "ConfirmReentryADX", "ConfirmReentryMACD", "EvaluateReentrySignal", "WeekendGuardEnabled", "ReadWeeklyBreak",
            "ResetWeekendGuard", "RefreshWeekendGuard", "SuperviseWeekendClose", "EvaluateATRDeviationSignal", "WickSignalSide", "EvaluateWickSignal", "OnTick",
        ], structures=["WeeklySession"], declarations=[
            "g_weekend_valid", "g_weekend_close", "g_weekend_problem",
        ])

    def test_wick_rejection_closed_signals(self):
        """Actual V6 OnTick: geometry, strict interior, ambiguity, timing and data failures."""
        self.check_scenario("wick", [
            "TargetInputs", "BarOf", "SignalSide", "TakeClosedBarOpportunity", "ClosedSignalSide", "ClearReentry", "Cooldown",
            "EvaluateClosedBarSignal", "ValidBBWInputs", "ConfirmReentryBBWP70", "ConfirmReentryBBW",
            "ReentryADXModeName", "ConfirmReentryADX", "ConfirmReentryMACD", "EvaluateReentrySignal",
            "EvaluateATRDeviationSignal", "WickSignalSide", "EvaluateWickSignal", "OnTick",
        ])

    def test_atr_deviation_preparation_and_management(self):
        """Actual ATR deviation OnTick: transitions, snapshots, gaps and SMA management."""
        self.check_scenario("atr_deviation", [
            "TargetInputs", "BarOf", "SignalSide", "TakeClosedBarOpportunity", "ClosedSignalSide", "ClearReentry", "Cooldown",
            "EvaluateClosedBarSignal", "ValidBBWInputs", "ConfirmReentryBBWP70", "ConfirmReentryBBW",
            "ReentryADXModeName", "ConfirmReentryADX", "ConfirmReentryMACD", "EvaluateReentrySignal",
            "EvaluateATRDeviationSignal", "WickSignalSide", "EvaluateWickSignal", "OnTick",
        ])

    def test_half_sma_exit_updates_with_fixed_entry(self):
        """Actual OnTick/Target: halfway SMA exit anchored to executed E1."""
        self.check_scenario("half_exit", [
            "Target", "HitTarget",
            "TargetInputs", "BarOf", "SignalSide", "TakeClosedBarOpportunity", "ClosedSignalSide", "ClearReentry", "Cooldown",
            "EvaluateClosedBarSignal", "ValidBBWInputs", "ConfirmReentryBBWP70", "ConfirmReentryBBW",
            "ReentryADXModeName", "ConfirmReentryADX", "ConfirmReentryMACD", "EvaluateReentrySignal",
            "EvaluateATRDeviationSignal", "WickSignalSide", "EvaluateWickSignal", "OnTick",
        ])

    def test_partial_exit_and_confirmed_atr_trailing(self):
        """Actual partial/history/trailing functions with broker requests and delayed events."""
        self.check_scenario("partial_trail", [
            "ManagementRetryIndex", "ManagementRequestAllowed", "RememberManagementResult",
            "Budget", "Price", "SamePrice", "Target", "Risk", "Levels", "Size", "StopDistance",
            "HitTarget", "ValidSL", "ValidTP", "HalfExitMode", "ResetHalfExit", "HalfKnownOrder", "HalfRememberOrder",
            "IgnoreHalfDeal", "HalfPosition", "Locked", "HalfVolumeValid", "HalfSplit", "HalfExitTransaction",
            "ReconcileHalfExit", "ObserveHalfExtreme", "HalfExitStep", "SyncTP", "SetInitialSL", "ATRAllowed", "OpenIdea", "InspectIdeaHistory",
        ], structures=["ManagementRetry"], declarations=[
            "MANAGEMENT_RETRY_SECONDS", "g_management_retries", "g_request_cycle", "g_market_retry_after",
        ])

    def test_partial_exit_on_tick_routing(self):
        """Actual OnTick: partial routing, trailing phase and money exit priority."""
        self.check_scenario("partial_route", [
            "Target", "HitTarget",
            "TargetInputs", "BarOf", "SignalSide", "TakeClosedBarOpportunity", "ClosedSignalSide", "ClearReentry", "Cooldown",
            "EvaluateClosedBarSignal", "ValidBBWInputs", "ConfirmReentryBBWP70", "ConfirmReentryBBW",
            "ReentryADXModeName", "ConfirmReentryADX", "ConfirmReentryMACD", "EvaluateReentrySignal",
            "EvaluateATRDeviationSignal", "WickSignalSide", "EvaluateWickSignal", "OnTick",
        ])

    def test_signal_trace_fields_and_pause_age(self):
        """Actual formatter: coherent OHLC/indicators, quote separation and elapsed time."""
        self.check_scenario("signal_trace", ["OscillatorSnapshot", "SignalLog"])
        self.check_scenario("wick_trace", ["ValidBBWInputs", "WickSignalSide", "EvaluateWickSignal"])
        self.check_scenario("atr_deviation_trace", ["ClearReentry", "EvaluateATRDeviationSignal"])


if __name__ == "__main__":
    unittest.main()
