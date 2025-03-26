///////////////////////////////////////////////////////////////////////////////
// File: dual_protocol_master_bfm.sv
// Description: Combined AHB and AXI4 Master BFM
// Author: anisbensiad
// Date: 2025-02-20 03:11:08
///////////////////////////////////////////////////////////////////////////////

interface dual_protocol_master_bfm #(
    // AXI4 Parameters
    parameter AXI_ADDR_WIDTH = 32,
    parameter AXI_DATA_WIDTH = 64,
    parameter AXI_ID_WIDTH   = 4,
    parameter AXI_USER_WIDTH = 4,
    parameter AXI_LEN_WIDTH  = 8,
    // AHB Parameters
    parameter AHB_ADDR_WIDTH = 32,
    parameter AHB_DATA_WIDTH = 32
)(
    // Common signals
    input logic clk,
    input logic rst_n
);

    // AHB Master Interface
    logic                        hsel;
    logic [AHB_ADDR_WIDTH-1:0]  haddr;
    logic [AHB_DATA_WIDTH-1:0]  hwdata;
    logic [AHB_DATA_WIDTH-1:0]  hrdata;
    logic                       hwrite;
    logic [2:0]                 hsize;
    logic [2:0]                 hburst;
    logic [1:0]                 htrans;
    logic                       hready;
    logic                       hresp;
    logic                       hbusreq;
    logic                       hgrant;
    logic [3:0]                 hprot;
    logic                       hmaster;
    logic                       hmastlock;

    // AXI4 Master Interface
    logic [AXI_ID_WIDTH-1:0]     awid;
    logic [AXI_ADDR_WIDTH-1:0]   awaddr;
    logic [AXI_LEN_WIDTH-1:0]    awlen;
    logic [2:0]                  awsize;
    logic [1:0]                  awburst;
    logic                        awlock;
    logic [3:0]                  awcache;
    logic [2:0]                  awprot;
    logic [3:0]                  awqos;
    logic [AXI_USER_WIDTH-1:0]   awuser;
    logic                        awvalid;
    logic                        awready;

    logic [AXI_DATA_WIDTH-1:0]   wdata;
    logic [AXI_DATA_WIDTH/8-1:0] wstrb;
    logic                        wlast;
    logic [AXI_USER_WIDTH-1:0]   wuser;
    logic                        wvalid;
    logic                        wready;

    logic [AXI_ID_WIDTH-1:0]     bid;
    logic [1:0]                  bresp;
    logic [AXI_USER_WIDTH-1:0]   buser;
    logic                        bvalid;
    logic                        bready;

    logic [AXI_ID_WIDTH-1:0]     arid;
    logic [AXI_ADDR_WIDTH-1:0]   araddr;
    logic [AXI_LEN_WIDTH-1:0]    arlen;
    logic [2:0]                  arsize;
    logic [1:0]                  arburst;
    logic                        arlock;
    logic [3:0]                  arcache;
    logic [2:0]                  arprot;
    logic [3:0]                  arqos;
    logic [AXI_USER_WIDTH-1:0]   aruser;
    logic                        arvalid;
    logic                        arready;

    logic [AXI_ID_WIDTH-1:0]     rid;
    logic [AXI_DATA_WIDTH-1:0]   rdata;
    logic [1:0]                  rresp;
    logic                        rlast;
    logic [AXI_USER_WIDTH-1:0]   ruser;
    logic                        rvalid;
    logic                        rready;

    // Enums for transaction types
    typedef enum logic [1:0] {
        IDLE   = 2'b00,
        BUSY   = 2'b01,
        NONSEQ = 2'b10,
        SEQ    = 2'b11
    } ahb_trans_t;

    typedef enum logic [2:0] {
        SINGLE = 3'b000,
        INCR   = 3'b001,
        WRAP4  = 3'b010,
        INCR4  = 3'b011,
        WRAP8  = 3'b100,
        INCR8  = 3'b101,
        WRAP16 = 3'b110,
        INCR16 = 3'b111
    } ahb_burst_t;

    typedef enum logic [1:0] {
        AXI_FIXED = 2'b00,
        AXI_INCR  = 2'b01,
        AXI_WRAP  = 2'b10
    } axi_burst_t;

    // Initialize interfaces
    task automatic init();
        // Initialize AHB signals
        hsel      = 0;
        haddr     = '0;
        hwdata    = '0;
        hwrite    = 0;
        hsize     = '0;
        hburst    = '0;
        htrans    = IDLE;
        hbusreq   = 0;
        hprot     = '0;
        hmastlock = 0;

        // Initialize AXI signals
        awid     = '0;
        awaddr   = '0;
        awlen    = '0;
        awsize   = '0;
        awburst  = '0;
        awlock   = '0;
        awcache  = '0;
        awprot   = '0;
        awqos    = '0;
        awuser   = '0;
        awvalid  = '0;

        wdata    = '0;
        wstrb    = '0;
        wlast    = '0;
        wuser    = '0;
        wvalid   = '0;

        bready   = '0;

        arid     = '0;
        araddr   = '0;
        arlen    = '0;
        arsize   = '0;
        arburst  = '0;
        arlock   = '0;
        arcache  = '0;
        arprot   = '0;
        arqos    = '0;
        aruser   = '0;
        arvalid  = '0;

        rready   = '0;
    endtask

    // AHB Write Transaction
    task automatic ahb_write(
        input logic [AHB_ADDR_WIDTH-1:0] addr,
        input logic [AHB_DATA_WIDTH-1:0] data,
        input ahb_burst_t burst_type = SINGLE,
        input logic [2:0] size = 3'b010 // Word size
    );
        // Request bus access
        @(posedge clk);
        hbusreq = 1;
        wait(hgrant);

        // Address phase
        @(posedge clk);
        hsel   = 1;
        haddr  = addr;
        hwrite = 1;
        hsize  = size;
        hburst = burst_type;
        htrans = NONSEQ;
        
        // Wait for ready
        wait(hready);

        // Data phase
        @(posedge clk);
        hwdata = data;
        htrans = IDLE;

        // Wait for completion
        wait(hready);
        
        // Release bus
        @(posedge clk);
        hsel    = 0;
        hbusreq = 0;
        hwrite  = 0;
    endtask

    // AHB Read Transaction
    task automatic ahb_read(
        input  logic [AHB_ADDR_WIDTH-1:0] addr,
        output logic [AHB_DATA_WIDTH-1:0] data,
        input  ahb_burst_t burst_type = SINGLE,
        input  logic [2:0] size = 3'b010
    );
        // Request bus access
        @(posedge clk);
        hbusreq = 1;
        wait(hgrant);

        // Address phase
        @(posedge clk);
        hsel   = 1;
        haddr  = addr;
        hwrite = 0;
        hsize  = size;
        hburst = burst_type;
        htrans = NONSEQ;
        
        // Wait for ready
        wait(hready);

        // Data phase
        @(posedge clk);
        htrans = IDLE;
        
        // Capture read data
        wait(hready);
        data = hrdata;
        
        // Release bus
        @(posedge clk);
        hsel    = 0;
        hbusreq = 0;
    endtask

    // AXI4 Write Transaction
    task automatic axi_write(
        input logic [AXI_ADDR_WIDTH-1:0] addr,
        input logic [AXI_DATA_WIDTH-1:0] data,
        input logic [AXI_LEN_WIDTH-1:0]  len = 0,
        input axi_burst_t burst_type = AXI_INCR
    );
        // Write Address Phase
        @(posedge clk);
        awaddr  = addr;
        awlen   = len;
        awburst = burst_type;
        awvalid = 1'b1;
        
        wait(awready);
        @(posedge clk);
        awvalid = 1'b0;
        
        // Write Data Phase
        wdata  = data;
        wstrb  = {(AXI_DATA_WIDTH/8){1'b1}};
        wlast  = 1'b1;
        wvalid = 1'b1;
        
        wait(wready);
        @(posedge clk);
        wvalid = 1'b0;
        
        // Write Response Phase
        bready = 1'b1;
        wait(bvalid);
        @(posedge clk);
        bready = 1'b0;
    endtask

    // AXI4 Read Transaction
    task automatic axi_read(
        input  logic [AXI_ADDR_WIDTH-1:0] addr,
        output logic [AXI_DATA_WIDTH-1:0] data,
        input  logic [AXI_LEN_WIDTH-1:0]  len = 0,
        input  axi_burst_t burst_type = AXI_INCR
    );
        // Read Address Phase
        @(posedge clk);
        araddr  = addr;
        arlen   = len;
        arburst = burst_type;
        arvalid = 1'b1;
        
        wait(arready);
        @(posedge clk);
        arvalid = 1'b0;
        
        // Read Data Phase
        rready = 1'b1;
        wait(rvalid);
        data = rdata;
        
        @(posedge clk);
        rready = 1'b0;
    endtask

    // Combined protocol write transaction
    task automatic write_transaction(
        input logic [AXI_ADDR_WIDTH-1:0] addr,
        input logic [AXI_DATA_WIDTH-1:0] data,
        input bit use_ahb = 0
    );
        if (use_ahb) begin
            ahb_write(addr, data[AHB_DATA_WIDTH-1:0]);
            if (AXI_DATA_WIDTH > AHB_DATA_WIDTH) begin
                ahb_write(addr + (AHB_DATA_WIDTH/8), data[AXI_DATA_WIDTH-1:AHB_DATA_WIDTH]);
            end
        end else begin
            axi_write(addr, data);
        end
    endtask

    // Combined protocol read transaction
    task automatic read_transaction(
        input  logic [AXI_ADDR_WIDTH-1:0] addr,
        output logic [AXI_DATA_WIDTH-1:0] data,
        input  bit use_ahb = 0
    );
        logic [AHB_DATA_WIDTH-1:0] temp_data;
        
        if (use_ahb) begin
            ahb_read(addr, temp_data);
            data[AHB_DATA_WIDTH-1:0] = temp_data;
            if (AXI_DATA_WIDTH > AHB_DATA_WIDTH) begin
                ahb_read(addr + (AHB_DATA_WIDTH/8), temp_data);
                data[AXI_DATA_WIDTH-1:AHB_DATA_WIDTH] = temp_data;
            end
        end else begin
            axi_read(addr, data);
        end
    endtask

endinterface