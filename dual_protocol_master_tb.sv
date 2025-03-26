///////////////////////////////////////////////////////////////////////////////
// File: dual_protocol_master_tb.sv
// Description: Testbench for Dual Protocol Master BFM
// Author: anisbensiad
// Created: 2025-02-20 03:13:56
///////////////////////////////////////////////////////////////////////////////

module dual_protocol_master_tb;

    // Clock and reset signals
    logic clk;
    logic rst_n;

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Reset generation
    initial begin
        rst_n = 0;
        #100;
        rst_n = 1;
    end

    // Instantiate the BFM
    dual_protocol_master_bfm #(
        .AXI_ADDR_WIDTH(32),
        .AXI_DATA_WIDTH(64),
        .AXI_ID_WIDTH(4),
        .AXI_USER_WIDTH(4),
        .AXI_LEN_WIDTH(8),
        .AHB_ADDR_WIDTH(32),
        .AHB_DATA_WIDTH(32)
    ) bfm (
        .clk(clk),
        .rst_n(rst_n)
    );

    // Test stimulus
    initial begin
        dual_protocol_command_parser parser;
        
        // Wait for reset to complete
        wait(rst_n);
        #100;

        // Initialize the BFM
        bfm.init();

        // Create parser instance
        parser = new("example_dual_protocol_commands.txt", bfm);
        
        // Parse and execute commands
        parser.parse_and_execute();

        // Add additional test scenarios here...
        
        #1000;
        $finish;
    end

    // Optional: Add protocol checkers and coverage collection
    
endmodule