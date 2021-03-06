// DESIGN SPECIFIC
`define ALU_BUS_WITH 		16
`define ALU_AMM_ADDR_WITH 	8
`define ALU_AMM_DATA_WITH	8   

/**

== Input packets ==

Header beat
+-----------------+--------------+---------------+------------------+
| reserved[15:12] | opcode[11:8] | reserved[7:6] | nof_operands[5:0]|
+-----------------+--------------+---------------+------------------+

Payload beat
+-----------------+----------+----------------------+
| reserved[15:10] | mod[9:8] | operands/address[7:0]|
+-----------------+----------+----------------------+

== Output packets ==

Header beat

+----------------+----------+-------------+
| reserved[15:5] | error[4] | opcode[3:0] |
+----------------+----------+-------------+

Payload beat

+-----------------+--------------+
| reserved[15:12] | result[11:0] |
+-----------------+--------------+

*/

module alu(
	 // Output interface
    output[`ALU_BUS_WITH - 1:0] data_out,
	 output 							  valid_out,
	 output 							  cmd_out,

	 //Input interface
	 input [`ALU_BUS_WITH - 1:0] data_in,
	 input 							  valid_in,
	 input 							  cmd_in,
	 
	 // AMM interface
	 output reg								 amm_read,
	 output reg [`ALU_AMM_ADDR_WITH - 1:0]  amm_address,
	 input [`ALU_AMM_DATA_WITH - 1:0] amm_readdata,
	 input 									 amm_waitrequest,
	 input[1:0] 							 amm_response,
	 
	 
	 //clock and reset interface
	 input clk,
	 input rst_n
    );
	 
	 `define ADD 			0
	 `define AND			1
	 `define OR				2
	 `define XOR			3
	 `define NOT			4
	 `define INC			5
	 `define DEC			6
	 `define NEG			7
	 `define SHR			8
	 `define SHL			9
	 
	 
	`define reset 							0			
	`define read_header					10
	`define read_payload 				20
	`define decode_payload				30
	`define decode_amm					35					
	`define execute						40
	`define generate_output_header 	50
	`define generate_output_payload  60
	
	//sequential regs
	reg[`ALU_BUS_WITH - 1:0] state = `reset, state_next; //starile automatului
	reg[5:0] counter, counter_next; // index pentru payload_buffer
	reg[11:0] sum, sum_next; //rezultat pt ADD
	reg[7:0] result, result_next; // rezultat pentru celelalte operatii
	
	//header_in regs
	reg [`ALU_BUS_WITH - 1:0] header; 
	reg [3:0] opcode; 
	reg [5:0] nof_operands_header;
	
	reg [6:0] i;
	/*
	wire [3:0] opcode;
	wire [5:0] nof_operands;
	*/
	
	//payload_in regs
	reg [9:0] payload_buffer[63:0];
	reg [`ALU_AMM_DATA_WITH - 1:0] operands[63:0];
	reg [1:0] mod; 
	
	reg boolean_error; //boolean pentru erori intalnite(nof_operands ==0 && amm_response != 2'b00); 1 pentru true si 0 pt false
	
	//data_out regs;
	//reg [15:0] header_out;
	//reg [15:0] payload_out;
	reg valid_out_reg;
	reg cmd_out_reg;
	reg [15:0] data_out_reg;
	
	assign data_out = data_out_reg;
	assign valid_out = valid_out_reg;
	assign cmd_out = cmd_out_reg;
	
	/*
	assign opcode = header[11:8];
	assign nof_operands = header[5:0]; 
	*/
	
	// FSM - sequential part
	always@(posedge clk) begin
	
		 state <= state_next;
		 counter <= counter_next; //index pentru payload_buffer
		 sum <= sum_next; //in sum calculez suma pentru ADD
		 result <= result_next; // in rezultat calculez operatiile 1-9;
		 
		 if(rst_n == 0) begin
			  state <= `reset;
			
			  /*
			  counter <= 6'b0;
			  sum <= 12'b0;
			  boolean_error = 0;
			  */
		 end
	 end
	
	always@(*) begin
		//state_next = `reset;
		
		//boolean_error = 0;
		//sum_next = 12'b0;
		//counter_next = 6'b0;
		
		case(state)
			
			`reset: begin
				state_next = `read_header;
				for(i = 0; i <= 63; i = i + 1)
					payload_buffer[i] = 10'b0;
				for(i = 0; i <= 63; i = i + 1)
					operands[i] = 8'b0;
				
				nof_operands_header = 6'b0;
				data_out_reg = 0;
				valid_out_reg = 0;
				cmd_out_reg= 0;
				boolean_error = 0;
				sum_next = 12'b0;
				counter_next = 6'b0;
				mod = 2'b00;
				result_next = 8'b0;
				
			end
			
			`read_header: begin 
				if(valid_in == 1 && cmd_in == 1) begin
				
					header = data_in; //citesc date pentru header
					opcode = header[11:8]; //codul operatiei din header
					nof_operands_header = header[5:0];
					
					if(nof_operands_header == 0) begin //caz de eroare
						boolean_error = 1; // am intalnit eroare
						state_next = `generate_output_header; //fac trecerea la output, nu am date de preluat din payload;
					end
					
					else 
						state_next = `read_payload;
				end
			   else 
					state_next = `read_header;
				
			end
	
			`read_payload: begin 
				if(valid_in == 1 && cmd_in == 0) begin
					//if(counter_next < nof_operands_header) begin 
					//execut operatii de citire din payload cat timp nr acestora este egal cu numarul de operanzi din header
						payload_buffer[counter_next] = data_in[9:0];
						counter_next = counter + 1;
						 
						
						if(counter_next == nof_operands_header) begin
							state_next = `decode_payload;
							counter_next = 0;
						end
						else
							state_next = `read_payload;
						
				end
			//end
				
				else if(valid_in == 0)
					state_next = `read_payload;
				
			end
				
			`decode_payload: begin
				if(counter < nof_operands_header - 1) begin
					mod = payload_buffer[counter_next][9:8];
					if(mod == 2'b00) begin //adresare imediata
						operands[counter_next] = payload_buffer[counter_next][7:0]; //introduc valori in buffer
						counter_next = counter + 1;
						
						if(counter_next== nof_operands_header) begin
							state_next = `execute;
							counter_next = 0;
						end
						
						else if(counter_next < nof_operands_header && counter_next != 6'b0)
							state_next = `decode_payload;
					end
					else begin //adresare indirecta
						amm_read = 1; //incep operatie de citire din memorie
						amm_address = payload_buffer[counter_next][7:0]; //constant
						if(amm_waitrequest)
							state_next = `decode_amm;
					end
				end
				else begin
					state_next = `execute;
					counter_next = 0;
				end
			end
				
			`decode_amm: begin
				
				if(amm_waitrequest)
					state_next = `decode_amm;
				else begin
					if(amm_response == 0) begin
						operands[counter_next] = amm_readdata[7:0];
						counter_next = counter + 1;
					end
					else
						boolean_error = 1;
						
					if(boolean_error == 1)
						state_next = `generate_output_header;
					else if(counter_next == nof_operands_header) begin
						state_next = `execute;
						counter_next = 0;
					end
					else if(counter_next < nof_operands_header && counter_next != 6'b0)
						state_next = `decode_payload;
						
				end
				
			end
				
						
			`execute: begin // implementarea operatilor necesare pt alu
				case(opcode)
					
					`ADD: begin
						if(counter_next < nof_operands_header) begin
							sum_next = sum + operands[counter_next];
						end
					end
					
					`AND: begin
						if(counter_next < nof_operands_header) begin
							result_next = result_next + operands[counter_next];
						end
					end
							
				endcase
				
					counter_next = counter + 1;
				if(counter_next == nof_operands_header)
					state_next = `generate_output_header;
				else
					state_next = `execute;
			end
			
			`generate_output_header: begin //output pt headear
				valid_out_reg = 1;
				cmd_out_reg = 1;
				if(valid_out_reg == 1 && cmd_out_reg == 1) begin
					if(boolean_error == 1)
						data_out_reg[15:0] = {11'b0, 1'b1, opcode};
					else 
						data_out_reg[15:0] = {11'b0, 1'b0, opcode};
				end	
				state_next = `generate_output_payload;
				
			end
			
			`generate_output_payload: begin //output pt payload
				valid_out_reg = 1;
				cmd_out_reg = 0;
				if(valid_out_reg == 1 && cmd_out_reg == 0) begin
					if(boolean_error == 0)
						data_out_reg[15:0] = {4'b0, sum_next};
					else 
						data_out_reg[15:0] = {4'b0, 12'hBAD};
				end
				
				//reinitializarea valorilor pentru urmatorul header
				
				state_next = `reset;
			end
		
		endcase
	end
endmodule
