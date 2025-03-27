interface dual_protocol_master_bfm (
    input logic clk,
    input logic rst_n
);
    // AHB Signals
    logic        ahb_hsel;
    logic [31:0] ahb_haddr;
    logic [2:0]  ahb_hsize;
    logic [2:0]  ahb_hburst;
    logic [1:0]  ahb_htrans;
    logic        ahb_hwrite;
    logic [31:0] ahb_hwdata;
    logic        ahb_hready;
    logic [31:0] ahb_hrdata;
    logic        ahb_hresp;

    // AXI Signals
    // Write Address Channel
    logic        axi_awvalid;
    logic        axi_awready;
    logic [31:0] axi_awaddr;
    logic [7:0]  axi_awlen;
    logic [2:0]  axi_awsize;
    logic [1:0]  axi_awburst;
    
    // Write Data Channel
    logic        axi_wvalid;
    logic        axi_wready;
    logic [63:0] axi_wdata;
    logic [7:0]  axi_wstrb;
    logic        axi_wlast;
    
    // Write Response Channel
    logic        axi_bvalid;
    logic        axi_bready;
    logic [1:0]  axi_bresp;
    
    // Read Address Channel
    logic        axi_arvalid;
    logic        axi_arready;
    logic [31:0] axi_araddr;
    logic [7:0]  axi_arlen;
    logic [2:0]  axi_arsize;
    logic [1:0]  axi_arburst;
    
    // Read Data Channel
    logic        axi_rvalid;
    logic        axi_rready;
    logic [63:0] axi_rdata;
    logic        axi_rlast;
    logic [1:0]  axi_rresp;

    // AHB Tasks
    task automatic ahb_write(
        input logic [31:0] address,
        input logic [31:0] data,
        input logic [2:0]  burst,
        input logic [2:0]  size
    );
        // Setup phase
        @(posedge clk);
        ahb_hsel   = 1'b1;
        ahb_haddr  = address;
        ahb_hsize  = size;
        ahb_hburst = burst;
        ahb_htrans = 2'b10;  // Non-sequential
        ahb_hwrite = 1'b1;
        
        // Wait for ready
        while (!ahb_hready) @(posedge clk);
        
        // Data phase
        ahb_hwdata = data;
        @(posedge clk);
        
        // Reset control signals
        ahb_hsel   = 1'b0;
        ahb_htrans = 2'b00;  // IDLE
        ahb_hwrite = 1'b0;
    endtask

    task automatic ahb_read(
        input  logic [31:0] address,
        output logic [31:0] data,
        input  logic [2:0]  burst,
        input  logic [2:0]  size
    );
        // Setup phase
        @(posedge clk);
        ahb_hsel   = 1'b1;
        ahb_haddr  = address;
        ahb_hsize  = size;
        ahb_hburst = burst;
        ahb_htrans = 2'b10;  // Non-sequential
        ahb_hwrite = 1'b0;
        
        // Wait for ready
        while (!ahb_hready) @(posedge clk);
        
        // Data phase
        @(posedge clk);
        data = ahb_hrdata;
        
        // Reset control signals
        ahb_hsel   = 1'b0;
        ahb_htrans = 2'b00;  // IDLE
    endtask

    // AXI Tasks
    task automatic axi_write(
        input logic [31:0] address,
        input logic [63:0] data,
        input logic [7:0]  len,
        input logic [1:0]  burst_type
    );
        // Address Phase
        @(posedge clk);
        axi_awvalid = 1'b1;
        axi_awaddr  = address;
        axi_awlen   = len;
        axi_awburst = burst_type;
        axi_awsize  = 3'b011;  // 8 bytes
        
        while (!axi_awready) @(posedge clk);
        @(posedge clk);
        axi_awvalid = 1'b0;
        
        // Data Phase
        axi_wvalid = 1'b1;
        axi_wdata  = data;
        axi_wstrb  = 8'hFF;
        axi_wlast  = 1'b1;
        
        while (!axi_wready) @(posedge clk);
        @(posedge clk);
        axi_wvalid = 1'b0;
        
        // Response Phase
        axi_bready = 1'b1;
        while (!axi_bvalid) @(posedge clk);
        @(posedge clk);
        axi_bready = 1'b0;
    endtask

    task automatic axi_read(
        input  logic [31:0] address,
        output logic [63:0] data,
        input  logic [7:0]  len,
        input  logic [1:0]  burst_type
    );
        // Address Phase
        @(posedge clk);
        axi_arvalid = 1'b1;
        axi_araddr  = address;
        axi_arlen   = len;
        axi_arburst = burst_type;
        axi_arsize  = 3'b011;  // 8 bytes
        
        while (!axi_arready) @(posedge clk);
        @(posedge clk);
        axi_arvalid = 1'b0;
        
        // Data Phase
        axi_rready = 1'b1;
        while (!axi_rvalid) @(posedge clk);
        data = axi_rdata;
        
        while (!axi_rlast) begin
            @(posedge clk);
            if (axi_rvalid) data = axi_rdata;
        end
        
        @(posedge clk);
        axi_rready = 1'b0;
    endtask

    // Initial block for signal initialization
    initial begin
        // Initialize AHB signals
        ahb_hsel   = 1'b0;
        ahb_haddr  = '0;
        ahb_hsize  = '0;
        ahb_hburst = '0;
        ahb_htrans = '0;
        ahb_hwrite = 1'b0;
        ahb_hwdata = '0;

        // Initialize AXI signals
        axi_awvalid = 1'b0;
        axi_awaddr  = '0;
        axi_awlen   = '0;
        axi_awsize  = '0;
        axi_awburst = '0;
        axi_wvalid  = 1'b0;
        axi_wdata   = '0;
        axi_wstrb   = '0;
        axi_wlast   = 1'b0;
        axi_bready  = 1'b0;
        axi_arvalid = 1'b0;
        axi_araddr  = '0;
        axi_arlen   = '0;
        axi_arsize  = '0;
        axi_arburst = '0;
        axi_rready  = 1'b0;
    end

endinterface
