#!/usr/bin/env python3
"""
PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
File: tests/test_ddr5_timings.py
Description: Verification of JEDEC DDR5 SDRAM AC timing constraints,
             bank state machine, row buffer page hits, and timing enforcement.

Author: Aneesh Krishna Parthasarathy
License: ISC License
"""

import unittest

class Ddr5BankState:
    IDLE = 0
    ACTIVATING = 1
    ACTIVE = 2
    PRECHARGING = 3

class Ddr5TimingModel:
    def __init__(self, t_rcd=14, t_rp=14, t_ras=32, t_wr=30, t_ccd_s=4):
        self.t_rcd = t_rcd
        self.t_rp = t_rp
        self.t_ras = t_ras
        self.t_wr = t_wr
        self.t_ccd_s = t_ccd_s

        self.bank_state = [Ddr5BankState.IDLE] * 32
        self.open_row = [-1] * 32
        self.bank_timer = [0] * 32
        self.cycle = 0

    def step_cycle(self):
        self.cycle += 1
        for b in range(32):
            if self.bank_timer[b] > 0:
                self.bank_timer[b] -= 1
                if self.bank_timer[b] == 0:
                    if self.bank_state[b] == Ddr5BankState.ACTIVATING:
                        self.bank_state[b] = Ddr5BankState.ACTIVE
                    elif self.bank_state[b] == Ddr5BankState.PRECHARGING:
                        self.bank_state[b] = Ddr5BankState.IDLE

    def can_activate(self, bank: int) -> bool:
        return self.bank_state[bank] == Ddr5BankState.IDLE and self.bank_timer[bank] == 0

    def activate(self, bank: int, row: int):
        assert self.can_activate(bank), f"Cannot activate bank {bank} in state {self.bank_state[bank]}"
        self.bank_state[bank] = Ddr5BankState.ACTIVATING
        self.open_row[bank] = row
        self.bank_timer[bank] = self.t_rcd

    def can_read(self, bank: int, row: int) -> bool:
        return (self.bank_state[bank] == Ddr5BankState.ACTIVE and
                self.open_row[bank] == row and
                self.bank_timer[bank] == 0)

    def read(self, bank: int, row: int):
        assert self.can_read(bank, row), f"Cannot read bank {bank}"
        self.bank_timer[bank] = self.t_ccd_s

    def can_precharge(self, bank: int) -> bool:
        return self.bank_state[bank] == Ddr5BankState.ACTIVE and self.bank_timer[bank] == 0

    def precharge(self, bank: int):
        assert self.can_precharge(bank), f"Cannot precharge bank {bank}"
        self.bank_state[bank] = Ddr5BankState.PRECHARGING
        self.open_row[bank] = -1
        self.bank_timer[bank] = self.t_rp

class TestDdr5Timings(unittest.TestCase):
    def test_activate_to_read_latency(self):
        model = Ddr5TimingModel(t_rcd=14, t_rp=14)
        bank = 5
        row = 0x0123

        # Must be able to activate when idle
        self.assertTrue(model.can_activate(bank))
        model.activate(bank, row)

        # Immediate read must fail (tRCD in progress)
        self.assertFalse(model.can_read(bank, row))

        # Advance 13 cycles, still activating
        for _ in range(13):
            model.step_cycle()
        self.assertFalse(model.can_read(bank, row))

        # Advance 1 more cycle (14 total): bank is now active!
        model.step_cycle()
        self.assertTrue(model.can_read(bank, row))

    def test_page_hit_back_to_back(self):
        model = Ddr5TimingModel(t_rcd=14, t_ccd_s=4)
        bank = 0
        row = 0x00FF

        model.activate(bank, row)
        for _ in range(14):
            model.step_cycle()

        # First read
        self.assertTrue(model.can_read(bank, row))
        model.read(bank, row)

        # Back to back read stalls for tCCD_S (4 cycles)
        self.assertFalse(model.can_read(bank, row))
        for _ in range(4):
            model.step_cycle()

        # Second read permitted on same open row
        self.assertTrue(model.can_read(bank, row))

    def test_page_conflict_precharge_sequence(self):
        model = Ddr5TimingModel(t_rcd=14, t_rp=14)
        bank = 2
        row_a = 0x0001
        row_b = 0x0002

        model.activate(bank, row_a)
        for _ in range(14):
            model.step_cycle()

        # Cannot read row_b while row_a is open
        self.assertFalse(model.can_read(bank, row_b))

        # Precharge row_a
        self.assertTrue(model.can_precharge(bank))
        model.precharge(bank)

        # Advance tRP cycles
        for _ in range(14):
            model.step_cycle()

        # Now can activate row_b
        self.assertTrue(model.can_activate(bank))
        model.activate(bank, row_b)

if __name__ == "__main__":
    unittest.main()
