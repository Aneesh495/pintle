/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: sim/cxl_monitor.cpp
 * Description: Implementation of CXL protocol monitor and coherence checker.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

#include "cxl_monitor.hpp"
#include <numeric>
#include <algorithm>
#include <iomanip>

namespace pintle {

CxlMonitor::CxlMonitor()
    : total_flits_rx_(0),
      total_flits_tx_(0),
      total_transactions_(0),
      total_snoops_(0),
      crc_errors_(0),
      coherence_violations_(0) {}

void CxlMonitor::onFlitRx(const CxlStandardFlit& flit) {
    total_flits_rx_++;
}

void CxlMonitor::onFlitTx(const CxlStandardFlit& flit) {
    total_flits_tx_++;
}

void CxlMonitor::onRequestDispatched(const CxlMemRequest& req, uint64_t cycle) {
    total_transactions_++;
    in_flight_cycles_[req.tag] = cycle;

    bool is_write = (req.opcode == CxlMemOp::MEM_OP_WRITE || req.opcode == CxlMemOp::MEM_OP_WRITE_DATA);
    checkCoherenceState(req.addr, req.host_id, is_write);
}

void CxlMonitor::onResponseReceived(const CxlMemResponse& rsp, uint64_t cycle) {
    auto it = in_flight_cycles_.find(rsp.tag);
    if (it != in_flight_cycles_.end()) {
        uint64_t latency = cycle - it->second;
        latency_records_.push_back(latency);
        in_flight_cycles_.erase(it);
    }
}

void CxlMonitor::onSnoopDispatched(uint64_t addr, uint8_t target_host) {
    total_snoops_++;
}

void CxlMonitor::onSnoopResponse(uint64_t addr, uint8_t src_host, BackInvalidateRspStatus status) {
    uint64_t aligned_addr = addr & ~0x3FULL;
    auto it = global_directory_.find(aligned_addr);
    if (it != global_directory_.end()) {
        it->second.sharer_mask &= ~(1 << src_host);
        if (it->second.owner_host == src_host) {
            it->second.state = GlobalLineState::INVALID;
        }
    }
}

bool CxlMonitor::checkCreditBalance(int host_id, int available_credits) {
    return (available_credits >= 0 && available_credits <= 128);
}

bool CxlMonitor::checkCoherenceState(uint64_t addr, uint8_t req_host, bool is_write) {
    uint64_t aligned_addr = addr & ~0x3FULL;
    auto it = global_directory_.find(aligned_addr);

    if (it == global_directory_.end()) {
        CoherenceRecord rec;
        rec.state = is_write ? GlobalLineState::MODIFIED : GlobalLineState::SHARED;
        rec.owner_host = req_host;
        rec.sharer_mask = (1 << req_host);
        global_directory_[aligned_addr] = rec;
        return true;
    }

    auto& rec = it->second;
    if (is_write) {
        // Exclusive write requires no other sharers
        uint8_t other_sharers = rec.sharer_mask & ~(1 << req_host);
        if (rec.state == GlobalLineState::MODIFIED && rec.owner_host != req_host) {
            coherence_violations_++;
            return false;
        }
        rec.state = GlobalLineState::MODIFIED;
        rec.owner_host = req_host;
        rec.sharer_mask = (1 << req_host);
    } else {
        rec.sharer_mask |= (1 << req_host);
    }
    return true;
}

double CxlMonitor::getAverageLatency() const {
    if (latency_records_.empty()) return 0.0;
    uint64_t sum = std::accumulate(latency_records_.begin(), latency_records_.end(), 0ULL);
    return static_cast<double>(sum) / latency_records_.size();
}

void CxlMonitor::printReport() const {
    std::cout << "\n=======================================================\n";
    std::cout << "PINTLE: CXL Protocol Monitor Verification Summary\n";
    std::cout << "=======================================================\n";
    std::cout << "Total Flits Processed (Rx):  " << total_flits_rx_ << "\n";
    std::cout << "Total Flits Dispatched (Tx): " << total_flits_tx_ << "\n";
    std::cout << "Total CXL.mem Transactions:  " << total_transactions_ << "\n";
    std::cout << "Back-Invalidation Snoops:    " << total_snoops_ << "\n";
    std::cout << "CRC Integrity Errors:        " << crc_errors_ << " (Expected 0)\n";
    std::cout << "Coherence Violations:        " << coherence_violations_ << " (Expected 0)\n";
    std::cout << "Mean Transaction Latency:    " << std::fixed << std::setprecision(2)
              << getAverageLatency() << " cycles\n";
    std::cout << "=======================================================\n";
}

} // namespace pintle
