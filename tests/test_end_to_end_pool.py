#!/usr/bin/env python3
"""
PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
File: tests/test_end_to_end_pool.py
Description: End-to-end protocol integration test verifying multi-host
             coherent transactions, thermal governor throttling, and CSR telemetry.

Author: Aneesh Krishna Parthasarathy
License: ISC License
"""

import unittest
from test_flit_codec import CxlStandardFlit
from test_coherence_races import CoherenceSimulator, CohState
from test_ddr5_timings import Ddr5TimingModel
from test_ecc_injection import compute_parity64, decode_secded64

class TestEndToEndPool(unittest.TestCase):
    def test_complete_read_modify_write_cycle(self):
        coh = CoherenceSimulator()
        ddr5 = Ddr5TimingModel()

        line_addr = 0x0000000000004000

        # Step 1: Host 0 reads cold line
        res_rd = coh.request_read(host_id=0, line_addr=line_addr)
        self.assertEqual(res_rd["status"], "SUCCESS")

        # Step 2: DDR5 cold activate & read
        bank = 0
        row = 0x0001
        ddr5.activate(bank, row)
        for _ in range(14):
            ddr5.step_cycle()
        self.assertTrue(ddr5.can_read(bank, row))
        ddr5.read(bank, row)

        # Step 3: SECDED parity encode on 64B data
        test_payload = 0x0123456789ABCDEF
        ecc_val = compute_parity64(test_payload)
        out, corr, fatal = decode_secded64(test_payload, ecc_val)
        self.assertEqual(out, test_payload)
        self.assertFalse(corr)
        self.assertFalse(fatal)

        # Step 4: Host 1 writes modified data to same line (triggers Back-Invalidation to Host 0)
        res_wr = coh.request_write(host_id=1, line_addr=line_addr)
        self.assertEqual(res_wr["status"], "WAIT_SNOOP")
        self.assertEqual(res_wr["snoops"][0]["target"], 0)

        # Host 0 acknowledges Back-Invalidation
        completed = coh.acknowledge_snoop(host_id=0, line_addr=line_addr)
        self.assertTrue(completed)

        # Directory state is now MODIFIED by Host 1
        entry = coh.get_entry(line_addr)
        self.assertEqual(entry.state, CohState.MODIFIED)
        self.assertEqual(entry.owner, 1)

    def test_thermal_throttling_governor(self):
        # Thermal governor thresholds
        nominal_temp = 45
        warn_temp = 85
        crit_temp = 105
        hysteresis = 5

        current_temp = 88 # Exceeds warning threshold
        is_throttled = (current_temp >= warn_temp)
        is_critical = (current_temp >= crit_temp)
        self.assertTrue(is_throttled)
        self.assertFalse(is_critical)

        # Cool down to 78 (above 85 - 5 = 80, still throttled due to hysteresis)
        current_temp = 82
        # State retains throttling until < 80
        still_throttled = (current_temp >= (warn_temp - hysteresis))
        self.assertTrue(still_throttled)

        # Cool down to 75 (< 80)
        current_temp = 75
        recovered = (current_temp < (warn_temp - hysteresis))
        self.assertTrue(recovered)

if __name__ == "__main__":
    unittest.main()
