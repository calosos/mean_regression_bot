"""Static project contracts; these are not MQL5 compilation checks."""
import re
import unittest

from test.harness import code_mask, function, source


class SourceContractTests(unittest.TestCase):
    def test_default_experiment_and_indicator_parameters(self):
        text = code_mask(source())
        expected = {
            "InpSignalMode": "INTRABAR",
            "InpStochasticK": "14",
            "InpStochasticD": "3",
            "InpStochasticSlowing": "3",
            "InpRiskPercent": "0.25",
        }
        for name, value in expected.items():
            with self.subTest(parameter=name):
                match = re.search(rf"\binput\s+\w+\s+{name}\s*=\s*([^;]+);", text)
                self.assertIsNotNone(match)
                self.assertEqual(match[1].strip(), value)

    def test_only_standard_trade_include_and_no_external_infrastructure(self):
        text = source()
        self.assertEqual(re.findall(r"(?m)^\s*#include\s+(.+)", text), ["<Trade/Trade.mqh>"])
        code = code_mask(text)
        self.assertNotRegex(code, r"\b(?:WebRequest|SendMail|SendNotification|FileOpen|iCustom)\s*\(")
        self.assertNotRegex(code, r"(?m)^\s*#import\b")

    def test_excursion_diagnostics_never_control_trading_or_log_per_tick(self):
        text = source()
        for name in ["ObserveIdeaExcursions", "UpdateExcursions", "ReconcileIdeaPnl",
                     "DiagnosticOrderVolume", "ExitDiagnosticText"]:
            with self.subTest(function=name):
                body = code_mask(function(text, name))
                self.assertNotRegex(body, r"\btrade\s*\.|\b(?:BeginClose|CloseStep|Cooldown|OpenIdea|Log|Print\w*)\s*\(")
                self.assertNotRegex(body, r"\b(?:state|history_ok|cooldown_until|target|g_sl|lot)\s*=(?!=)")

    def test_initialization_retains_tester_and_usd_guards(self):
        init = function(source(), "OnInit")
        # Rejecting the environment happens before indicator creation/trade setup.
        tester_guard = init.index("if(!MQLInfoInteger(MQL_TESTER))")
        currency_guard = init.index('if(AccountInfoString(ACCOUNT_CURRENCY)!="USD")')
        self.assertLess(tester_guard, init.index("trade.SetExpertMagicNumber"))
        self.assertLess(currency_guard, init.index("trade.SetExpertMagicNumber"))
        self.assertIn("return INIT_FAILED;", init[tester_guard:currency_guard])
        self.assertIn("return INIT_PARAMETERS_INCORRECT;", init[currency_guard:init.index("trade.SetExpertMagicNumber")])


if __name__ == "__main__":
    unittest.main()
