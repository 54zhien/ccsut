import os
from pathlib import Path
import runpy
import subprocess
import unittest
from unittest.mock import patch


class DiagnosticExitTests(unittest.TestCase):
    def invoke(self, outcomes):
        script = Path(__file__).with_name('run-payment-model-diagnostics.py')
        with patch.dict(os.environ, {'CCSUT_PAYMENT_REPETITIONS': '1'}), \
             patch('sys.argv', [str(script), 'fixture-binary']), \
             patch('sys.platform', 'darwin'), \
             patch('subprocess.run', side_effect=outcomes) as run:
            try:
                runpy.run_path(str(script), run_name='__main__')
                return 0, run.call_count
            except SystemExit as result:
                return result.code, run.call_count

    def test_success_does_not_launch_debugger(self):
        self.assertEqual(self.invoke([subprocess.CompletedProcess([], 0)]), (0, 1))

    def test_assertion_failure_does_not_launch_debugger(self):
        self.assertEqual(self.invoke([subprocess.CompletedProcess([], 1)]), (1, 1))

    def test_successful_diagnostic_run_cannot_erase_crash(self):
        self.assertEqual(self.invoke([subprocess.CompletedProcess([], -11),
                                      subprocess.CompletedProcess([], 0)]), (139, 2))

    def test_debugger_timeout_cannot_replace_original_crash(self):
        self.assertEqual(self.invoke([subprocess.CompletedProcess([], -11),
                                      subprocess.TimeoutExpired('lldb', 90)]), (139, 2))


if __name__ == '__main__':
    unittest.main()
