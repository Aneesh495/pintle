/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: sim/dpi_bridge.cpp
 * Description: Direct Programming Interface (DPI-C) bridge implementation for
 *              CXL 3.1 co-simulation harness.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

#include "dpi_bridge.hpp"
#include "cxl_packet.hpp"
#include "cxl_monitor.hpp"
#include "cxl_host_agent.hpp"
#include <deque>
#include <mutex>
#include <iostream>

static std::unique_ptr<pintle::CxlMonitor> g_monitor;
static std::deque<pintle::CxlStandardFlit>  g_rx_queue;
static std::deque<pintle::CxlStandardFlit>  g_tx_queue;
static std::mutex                          g_mutex;
static uint64_t                            g_sim_cycle = 0;

extern "C" {

void dpi_cxl_init() {
    std::lock_guard<std::mutex> lock(g_mutex);
    g_monitor = std::make_unique<pintle::CxlMonitor>();
    g_rx_queue.clear();
    g_tx_queue.clear();
    g_sim_cycle = 0;
    std::cout << "[DPI-Bridge] PINTLE CXL 3.1 DPI Co-Simulation Bridge Initialized.\n";
}

void dpi_cxl_send_flit(const uint8_t* flit_bytes) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!flit_bytes) return;

    pintle::CxlStandardFlit flit;
    flit.flit_type = flit_bytes[0];
    flit.seq_num   = flit_bytes[1];
    flit.ack_num   = flit_bytes[2];
    flit.credit_tokens = flit_bytes[3];
    std::memcpy(flit.payload.data(), flit_bytes + 4, flit.payload.size());
    std::memcpy(&flit.crc, flit_bytes + 252, sizeof(uint32_t));

    if (g_monitor) {
        g_monitor->onFlitRx(flit);
    }
    g_rx_queue.push_back(flit);
}

int dpi_cxl_recv_flit(uint8_t* out_flit_bytes) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_tx_queue.empty() || !out_flit_bytes) {
        return 0;
    }

    auto flit = g_tx_queue.front();
    g_tx_queue.pop_front();

    out_flit_bytes[0] = flit.flit_type;
    out_flit_bytes[1] = flit.seq_num;
    out_flit_bytes[2] = flit.ack_num;
    out_flit_bytes[3] = flit.credit_tokens;
    std::memcpy(out_flit_bytes + 4, flit.payload.data(), flit.payload.size());
    std::memcpy(out_flit_bytes + 252, &flit.crc, sizeof(uint32_t));

    if (g_monitor) {
        g_monitor->onFlitTx(flit);
    }
    return 1;
}

void dpi_cxl_record_event(uint32_t event_type, uint64_t param) {
    // Record event
}

void dpi_cxl_step_cycle(uint64_t cycle) {
    g_sim_cycle = cycle;
}

uint32_t dpi_cxl_compute_crc32(const uint8_t* data, uint32_t len) {
    return pintle::compute_crc32c(data, len);
}

void dpi_cxl_print_summary() {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_monitor) {
        g_monitor->printReport();
    }
}

} // extern "C"
