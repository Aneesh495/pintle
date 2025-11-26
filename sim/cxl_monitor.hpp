/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: sim/cxl_monitor.hpp
 * Description: Real-time CXL protocol monitor and coherence invariant checker
 *              verifying credit rules, CRC integrity, and MOESI state safety.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

#ifndef PINTLE_CXL_MONITOR_HPP
#define PINTLE_CXL_MONITOR_HPP

#include "cxl_packet.hpp"
#include <unordered_map>
#include <vector>
#include <string>
#include <iostream>
#include <cassert>

namespace pintle {

enum class GlobalLineState {
    INVALID,
    SHARED,
    MODIFIED
};

struct CoherenceRecord {
    GlobalLineState state;
    uint8_t         owner_host;
    uint8_t         sharer_mask;
};

class CxlMonitor {
public:
    CxlMonitor();

    // Event capture
    void onFlitRx(const CxlStandardFlit& flit);
    void onFlitTx(const CxlStandardFlit& flit);
    void onRequestDispatched(const CxlMemRequest& req, uint64_t cycle);
    void onResponseReceived(const CxlMemResponse& rsp, uint64_t cycle);
    void onSnoopDispatched(uint64_t addr, uint8_t target_host);
    void onSnoopResponse(uint64_t addr, uint8_t src_host, BackInvalidateRspStatus status);

    // Invariant verifications
    bool checkCreditBalance(int host_id, int available_credits);
    bool checkCoherenceState(uint64_t addr, uint8_t req_host, bool is_write);

    // Reporting
    void printReport() const;
    size_t getTotalTransactions() const { return total_transactions_; }
    size_t getCoherenceViolations() const { return coherence_violations_; }
    size_t getCrcErrors() const { return crc_errors_; }
    double getAverageLatency() const;

private:
    std::unordered_map<uint64_t, CoherenceRecord> global_directory_;
    std::unordered_map<uint16_t, uint64_t> in_flight_cycles_;
    std::vector<uint64_t> latency_records_;

    size_t total_flits_rx_;
    size_t total_flits_tx_;
    size_t total_transactions_;
    size_t total_snoops_;
    size_t crc_errors_;
    size_t coherence_violations_;
};

} // namespace pintle

#endif // PINTLE_CXL_MONITOR_HPP
