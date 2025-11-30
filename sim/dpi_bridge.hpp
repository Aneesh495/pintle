/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: sim/dpi_bridge.hpp
 * Description: Direct Programming Interface (DPI-C) bridge declarations for
 *              hardware co-simulation and transaction logging.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

#ifndef PINTLE_DPI_BRIDGE_HPP
#define PINTLE_DPI_BRIDGE_HPP

#include <cstdint>

#ifdef __cplusplus
extern "C" {
#endif

void     dpi_cxl_init();
void     dpi_cxl_send_flit(const uint8_t* flit_bytes);
int      dpi_cxl_recv_flit(uint8_t* out_flit_bytes);
void     dpi_cxl_record_event(uint32_t event_type, uint64_t param);
void     dpi_cxl_step_cycle(uint64_t cycle);
uint32_t dpi_cxl_compute_crc32(const uint8_t* data, uint32_t len);
void     dpi_cxl_print_summary();

#ifdef __cplusplus
}
#endif

#endif // PINTLE_DPI_BRIDGE_HPP
