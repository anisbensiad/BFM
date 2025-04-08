///////////////////////////////////////////////////////////////////////////////
// Dual Protocol Command Parser
// Author: Anis Ben Said
//
// This class implements a command parser for the dual protocol BFM supporting both
// AHB and AXI protocols with configurable AXI data width (64/128 bits).
// The parser reads commands from a text file and validates read data against
// expected values when provided.
//
// Command Format:
// AHB WRITE <address> <data> [burst_type] [size]
// AHB READ <address> [burst_type] [size] [expected_data]
// AXI WRITE <address> <data> [burst_type] [length]
// AXI READ <address> [burst_type] [length] [expected_data]
// WAIT <cycles>
///////////////////////////////////////////////////////////////////////////////

class dual_protocol_command_parser #(
    parameter AXI_DATA_WIDTH = 64  // Supports 64 or 128 bits
);
    ///////////////////////////////////////////////////////////////////////////
    // Type Definitions
    ///////////////////////////////////////////////////////////////////////////

    // Protocol selection enumeration
    typedef enum {
        AHB,
        AXI,
        WAIT
    } protocol_t;

    // Command type enumeration
    typedef enum {
        CMD_WRITE,
        CMD_READ,
        CMD_BURST_WRITE,
        CMD_BURST_READ,
        CMD_WAIT
    } command_t;

    // AHB local enumerations
    typedef enum logic [2:0] {
        BYTE     = 3'b000,
        HALFWORD = 3'b001,
        WORD     = 3'b010
    } local_ahb_size_t;

    typedef enum logic [2:0] {
        SINGLE  = 3'b000,
        INCR    = 3'b001,
        INCR4   = 3'b011,
        INCR8   = 3'b101,
        INCR16  = 3'b111,
        WRAP4   = 3'b010,
        WRAP8   = 3'b100,
        WRAP16  = 3'b110
    } local_ahb_burst_t;

    // AXI local enumeration
    typedef enum logic [1:0] {
        AXI_FIXED = 2'b00,
        AXI_INCR  = 2'b01,
        AXI_WRAP  = 2'b10
    } local_axi_burst_t;

    // Test results tracking structure
    typedef struct {
        int total_tests;
        int passed_tests;
        int failed_tests;
        string last_error;
    } test_results_t;

    ///////////////////////////////////////////////////////////////////////////
    // Class Properties
    ///////////////////////////////////////////////////////////////////////////
    
    // File handling
    protected int file_handle;
    protected string filename;
    protected int line_number;
    protected string current_line;

    // BFM interface reference
    protected virtual dual_protocol_master_bfm #(AXI_DATA_WIDTH) bfm;

    // Test results
    test_results_t results;

    ///////////////////////////////////////////////////////////////////////////
    // Constructor
    ///////////////////////////////////////////////////////////////////////////

    function new(string filename, virtual dual_protocol_master_bfm #(AXI_DATA_WIDTH) bfm);
        this.filename = filename;
        this.bfm = bfm;
        this.line_number = 0;
        
        // Initialize results
        results.total_tests = 0;
        results.passed_tests = 0;
        results.failed_tests = 0;
        results.last_error = "";

        // Parameter validation
        if (!(AXI_DATA_WIDTH inside {64, 128})) begin
            $fatal(1, "Error: AXI_DATA_WIDTH must be either 64 or 128!");
        end
    endfunction

    ///////////////////////////////////////////////////////////////////////////
    // Public Tasks
    ///////////////////////////////////////////////////////////////////////////

    // Main task to parse and execute commands from file
    task automatic parse_and_execute();
        string command_tokens[$];

        // Open command file
        file_handle = $fopen(filename, "r");
        if (file_handle == 0) begin
            results.last_error = $sformatf("Could not open file %s", filename);
            $error("[%0t] %s", $time, results.last_error);
            return;
        end

        $display("[%0t] Starting command execution from file: %s", $time, filename);
        $display("[%0t] AXI Data Width configured as: %0d bits", $time, AXI_DATA_WIDTH);
        
        // Process commands
        while (!$feof(file_handle)) begin
            if (read_next_valid_line()) begin
                tokenize(current_line, command_tokens);
                if (command_tokens.size() > 0) begin
                    process_command_line(command_tokens);
                end
            end
        end

        $fclose(file_handle);
        report_results();
    endtask

    ///////////////////////////////////////////////////////////////////////////
    // Protected Tasks - Command Processing
    ///////////////////////////////////////////////////////////////////////////

    // Process a single command line
    protected task automatic process_command_line(string tokens[$]);
        protocol_t protocol;
        command_t command;

        if (parse_protocol_and_command(tokens, protocol, command)) begin
            case (protocol)
                AHB:  process_ahb_command(command, tokens);
                AXI:  process_axi_command(command, tokens);
                WAIT: process_wait_command(tokens);
            endcase
        end
    endtask

    // Process AHB commands
    protected task automatic process_ahb_command(command_t command, string tokens[$]);
        logic [31:0] address, data, expected_data;
        logic has_expected_data;
        local_ahb_burst_t burst_type = SINGLE;
        local_ahb_size_t size = WORD;
        int param_index;

        // Validate minimum token count
        if (tokens.size() < 3) begin
            $error("[%0t] Line %0d: Invalid AHB command format", $time, line_number);
            return;
        end

        // Parse address
        if (!parse_hex_value(tokens[2], address, 32)) return;

        case (command)
            CMD_WRITE: begin
                if (tokens.size() < 4) begin
                    $error("[%0t] Line %0d: Invalid AHB WRITE command format", $time, line_number);
                    return;
                end

                // Parse data
                if (!parse_hex_value(tokens[3], data, 32)) return;

                // Parse optional parameters
                if (tokens.size() > 4) burst_type = parse_ahb_burst_type(tokens[4]);
                if (tokens.size() > 5) size = parse_ahb_size(tokens[5]);

                // Execute write
                bfm.ahb_write(address, data, burst_type, size);
                $display("[%0t] Line %0d: AHB Write - Address: 0x%h, Data: 0x%h, Burst: %s, Size: %s",
                        $time, line_number, address, data, tokens[4], tokens[5]);
            end

            CMD_READ: begin
                param_index = 3;
                has_expected_data = 0;

                // Parse optional parameters
                if (tokens.size() > param_index && 
                    !(tokens[param_index] inside {"BYTE", "HALFWORD", "WORD"}) &&
                    !(tokens[param_index] inside {"SINGLE", "INCR", "INCR4", "INCR8", "INCR16", "WRAP4", "WRAP8", "WRAP16"})) begin
                    if (!parse_hex_value(tokens[param_index], expected_data, 32)) return;
                    has_expected_data = 1;
                end else begin
                    // Parse burst type and size if present
                    if (tokens.size() > param_index) burst_type = parse_ahb_burst_type(tokens[param_index++]);
                    if (tokens.size() > param_index) size = parse_ahb_size(tokens[param_index++]);
                    // Check for expected data after parameters
                    if (tokens.size() > param_index) begin
                        if (!parse_hex_value(tokens[param_index], expected_data, 32)) return;
                        has_expected_data = 1;
                    end
                end

                // Execute read
                bfm.ahb_read(address, data, burst_type, size);

                // Validate data if expected value was provided
                if (has_expected_data) begin
                    results.total_tests++;
                    if (data === expected_data) begin
                        results.passed_tests++;
                        $display("[%0t] Line %0d: AHB Read PASS - Address: 0x%h, Data: 0x%h", 
                                $time, line_number, address, data);
                    end else begin
                        results.failed_tests++;
                        results.last_error = $sformatf("AHB Read mismatch at 0x%h - Expected: 0x%h, Got: 0x%h",
                                                      address, expected_data, data);
                        $error("[%0t] Line %0d: %s", $time, line_number, results.last_error);
                    end
                end else begin
                    $display("[%0t] Line %0d: AHB Read - Address: 0x%h, Data: 0x%h, Burst: %s, Size: %s",
                            $time, line_number, address, data, burst_type.name(), size.name());
                end
            end
        endcase
    endtask

    // Process AXI commands
    protected task automatic process_axi_command(command_t command, string tokens[$]);
        logic [31:0] address;
        logic [AXI_DATA_WIDTH-1:0] data, expected_data;
        logic has_expected_data;
        local_axi_burst_t burst_type = AXI_INCR;
        logic [7:0] len = 0;
        int param_index;

        // Validate minimum token count
        if (tokens.size() < 3) begin
            $error("[%0t] Line %0d: Invalid AXI command format", $time, line_number);
            return;
        end

        // Parse address
        if (!parse_hex_value(tokens[2], address, 32)) return;

        case (command)
            CMD_WRITE, CMD_BURST_WRITE: begin
                if (tokens.size() < 4) begin
                    $error("[%0t] Line %0d: Invalid AXI WRITE command format", $time, line_number);
                    return;
                end

                // Parse data
                if (!parse_axi_data(tokens[3], data)) return;

                // Parse optional parameters
                if (tokens.size() > 4) burst_type = parse_axi_burst_type(tokens[4]);
                if (tokens.size() > 5) void'($sscanf(tokens[5], "%d", len));

                // Execute write
                bfm.axi_write(address, data, len, burst_type);
                $display("[%0t] Line %0d: AXI Write - Address: 0x%h, Data: 0x%h, Burst: %s, Length: %0d",
                        $time, line_number, address, data, burst_type.name(), len);
            end

            CMD_READ, CMD_BURST_READ: begin
                param_index = 3;
                has_expected_data = 0;

                // Check if we have burst type
                if (tokens.size() > param_index && 
                    (tokens[param_index] inside {"FIXED", "INCR", "WRAP"})) begin
                    burst_type = parse_axi_burst_type(tokens[param_index]);
                    param_index++;
                end

                // Check if we have length
                if (tokens.size() > param_index &&
                    tokens[param_index].len() <= 3 &&  // Assume length is small number
                    tokens[param_index][0] inside {"0","1","2","3","4","5","6","7","8","9"}) begin
                    void'($sscanf(tokens[param_index], "%d", len));
                    param_index++;
                end

                // Check if we have expected data
                if (tokens.size() > param_index) begin
                    has_expected_data = 1;
                    if (!parse_axi_data(tokens[param_index], expected_data)) return;
                end

                // Execute read
                bfm.axi_read(address, data, len, burst_type);

                // Validate data if expected value was provided
                if (has_expected_data) begin
                    results.total_tests++;
                    if (data === expected_data) begin
                        results.passed_tests++;
                        $display("[%0t] Line %0d: AXI Read PASS - Address: 0x%h, Data: 0x%h", 
                                $time, line_number, address, data);
                    end else begin
                        results.failed_tests++;
                        results.last_error = $sformatf("AXI Read mismatch at 0x%h - Expected: 0x%h, Got: 0x%h",
                                                      address, expected_data, data);
                        $error("[%0t] Line %0d: %s", $time, line_number, results.last_error);
                    end
                end else begin
                    $display("[%0t] Line %0d: AXI Read - Address: 0x%h, Data: 0x%h, Burst: %s, Length: %0d",
                            $time, line_number, address, data, burst_type.name(), len);
                end
            end
        endcase
    endtask

    // Process wait commands
    protected task automatic process_wait_command(string tokens[$]);
        int cycles;

        if (tokens.size() < 2) begin
            $error("[%0t] Line %0d: Invalid WAIT command format", $time, line_number);
            return;
        end

        void'($sscanf(tokens[1], "%d", cycles));
        $display("[%0t] Line %0d: Waiting for %0d cycles", $time, line_number, cycles);
        repeat(cycles) @(posedge dual_protocol_master_tb.clk_max);
    endtask

    ///////////////////////////////////////////////////////////////////////////
    // Protected Functions - Parsing Helpers
    ///////////////////////////////////////////////////////////////////////////

    // Parse protocol and command type
    protected function bit parse_protocol_and_command(
        string tokens[$],
        output protocol_t protocol,
        output command_t command
    );
        if (tokens.size() < 2) return 0;

        // Parse protocol
        case (tokens[0].toupper())
            "AHB": protocol = AHB;
            "AXI": protocol = AXI;
            "WAIT": begin
                protocol = WAIT;
                return 1;
            end
            default: begin
                $error("[%0t] Line %0d: Invalid protocol: %s", $time, line_number, tokens[0]);
                return 0;
            end
        endcase

        // Parse command
        case (tokens[1].toupper())
            "WRITE": command = CMD_WRITE;
            "READ":  command = CMD_READ;
            "BURST_WRITE": command = CMD_BURST_WRITE;
            "BURST_READ":  command = CMD_BURST_READ;
            default: begin
                $error("[%0t] Line %0d: Invalid command: %s", $time, line_number, tokens[1]);
                return 0;
            end
        endcase

        return 1;
    endfunction

    // Parse hex value with width checking
    protected function bit parse_hex_value(string hex_str, output logic [127:0] value, input int width);
        string trimmed_str = hex_str;
        
        // Remove '0x' prefix if present
        if (trimmed_str.len() >= 2 && trimmed_str.substr(0, 1) == "0x") begin
            trimmed_str = trimmed_str.substr(2, trimmed_str.len() - 1);
        end

        // Remove underscores
        trimmed_str = remove_underscores(trimmed_str);

        // Validate string length
        if (trimmed_str.len() > (width / 4)) begin
            $error("[%0t] Line %0d: Value %s exceeds %0d-bit width", 
                   $time, line_number, hex_str, width);
            return 0;
        end

        // Parse hex value
        if (!$sscanf(trimmed_str, "%h", value)) begin
            $error("[%0t] Line %0d: Invalid hex value: %s", $time, line_number, hex_str);
            return 0;
        end

        return 1;
    endfunction

    // Parse AXI data value
    protected function bit parse_axi_data(string data_str, output logic [AXI_DATA_WIDTH-1:0] data);
        logic [127:0] parsed_value;
        
        if (!parse_hex_value(data_str, parsed_value, AXI_DATA_WIDTH)) return 0;
        
        data = parsed_value[AXI_DATA_WIDTH-1:0];
        return 1;
    endfunction

    // Remove underscores from string
    protected function string remove_underscores(string str);
        string result = "";
        foreach (str[i]) begin
            if (str[i] != "_") result = {result, string'(str[i])};
        end
        return result;
    endfunction

    // Read next valid line (skipping comments and empty lines)
    protected function bit read_next_valid_line();
        string line;
        
        while ($fgets(line, file_handle)) begin
            line_number++;
            current_line = strip_comments(line);
            
            // Skip empty lines
            if (current_line.len() > 0) return 1;
        end
        
        return 0;
    endfunction

    // Strip comments and whitespace
    protected function string strip_comments(string line);
        string result = "";
        int start_idx = 0;
        int end_idx = 0;
        
        // First strip comments
        foreach (line[i]) begin
            if (line[i] == "#") break;
            result = {result, string'(line[i])};
        end
        
        // Then remove leading whitespace
        start_idx = 0;
        while (start_idx < result.len() && 
              (result[start_idx] == " " || 
               result[start_idx] == "\t" || 
               result[start_idx] == "\n" || 
               result[start_idx] == "\r")) begin
            start_idx++;
        end
        
        // Find last non-whitespace character
        end_idx = result.len() - 1;
        while (end_idx >= 0 && 
              (result[end_idx] == " " || 
               result[end_idx] == "\t" || 
               result[end_idx] == "\n" || 
               result[end_idx] == "\r")) begin
            end_idx--;
        end
        
        // Return trimmed string
        if (start_idx <= end_idx)
            return result.substr(start_idx, end_idx);
        else
            return "";
    endfunction

    // Tokenize line into words
    protected function void tokenize(input string line, ref string tokens[$]);
        string remaining = line;
        int start_idx;
        int end_idx;
        
        tokens.delete();
        
        while (remaining.len() > 0) begin
            // Skip leading whitespace
            start_idx = 0;
            while (start_idx < remaining.len() && 
                  (remaining[start_idx] == " " || 
                   remaining[start_idx] == "\t" || 
                   remaining[start_idx] == "\n" || 
                   remaining[start_idx] == "\r")) begin
                start_idx++;
            end
            
            if (start_idx >= remaining.len()) break;
            
            // Find end of token
            end_idx = start_idx;
            while (end_idx < remaining.len() && 
                  !(remaining[end_idx] == " " || 
                    remaining[end_idx] == "\t" || 
                    remaining[end_idx] == "\n" || 
                    remaining[end_idx] == "\r")) begin
                end_idx++;
            end
            
            // Extract token
            tokens.push_back(remaining.substr(start_idx, end_idx-1));
            
            // Move to next token
            if (end_idx >= remaining.len())
                break;
            remaining = remaining.substr(end_idx, remaining.len()-1);
        end
    endfunction

    // Parse AHB burst type
    protected function local_ahb_burst_t parse_ahb_burst_type(string burst_str);
        case (burst_str.toupper())
            "SINGLE": return SINGLE;
            "INCR":   return INCR;
            "INCR4":  return INCR4;
            "INCR8":  return INCR8;
            "INCR16": return INCR16;
            "WRAP4":  return WRAP4;
            "WRAP8":  return WRAP8;
            "WRAP16": return WRAP16;
            default: begin
                $error("[%0t] Line %0d: Invalid AHB burst type: %s", 
                       $time, line_number, burst_str);
                return SINGLE;
            end
        endcase
    endfunction

    // Parse AHB size
    protected function local_ahb_size_t parse_ahb_size(string size_str);
        case (size_str.toupper())
            "BYTE":     return BYTE;
            "HALFWORD": return HALFWORD;
            "WORD":     return WORD;
            default: begin
                $error("[%0t] Line %0d: Invalid AHB size: %s", 
                       $time, line_number, size_str);
                return WORD;
            end
        endcase
    endfunction

    // Parse AXI burst type
    protected function local_axi_burst_t parse_axi_burst_type(string burst_str);
        case (burst_str.toupper())
            "FIXED": return AXI_FIXED;
            "INCR":  return AXI_INCR;
            "WRAP":  return AXI_WRAP;
            default: begin
                $error("[%0t] Line %0d: Invalid AXI burst type: %s", 
                       $time, line_number, burst_str);
                return AXI_INCR;
            end
        endcase
    endfunction

    ///////////////////////////////////////////////////////////////////////////
    // Results Reporting
    ///////////////////////////////////////////////////////////////////////////

    // Report test results
    task automatic report_results();
        $display("\n============ Test Results Summary ============");
        $display("Total Tests Run: %0d", results.total_tests);
        $display("Tests Passed:    %0d", results.passed_tests);
        $display("Tests Failed:    %0d", results.failed_tests);
        if (results.failed_tests > 0) begin
            $display("Last Error:      %s", results.last_error);
        end
        $display("==========================================\n");

        if (results.failed_tests > 0) begin
            $error("Test completed with %0d failures", results.failed_tests);
        end else if (results.total_tests > 0) begin
            $display("All %0d tests passed successfully!", results.total_tests);
        end else begin
            $display("No validation tests were performed");
        end
    endtask

endclass
