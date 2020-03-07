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
	 
	 
	`define reset 							0			//initializez reg-uri cu 0
	`define read_header					10			//citesc header
	`define read_payload 				20			//citesc payload
	`define decode_operand				30			//decodific valorile din payload pentru adresare imediata
	`define decode_amm					35			//preiau operanzii din memorie
	`define execute						40			//calculul operatiilor
	`define generate_output_header 	50			//header out
	`define generate_output_payload  60			//payload out
	
	
	
	//////////////////////////////////////////////////////////////////////////////
	
	//								REGS FOR SEQUENTIAL												
	reg[`ALU_BUS_WITH - 1:0] state = `reset, state_next; //starile automatului		
	reg[5:0] counter, counter_next; // index pentru payload_buffer						
	reg[11:0] sum, sum_next; //rezultat pt ADD												
	reg signed[7:0]  result, result_next; // rezultat pentru celelalte operatii	
	reg [5:0] counter_decod, counter_decod_next;// index pentru operand
	
	//////////////////////////////////////////////////////////////////////////////
	
	
	
	
	//////////////////////////////////////////////////////////////////////////////
	
	//								HEADER_IN REGS
	reg [`ALU_BUS_WITH - 1:0] header; //header_in
	reg [3:0] opcode; //codul operatiei
	reg [5:0] nof_operands_header; //numar de operanzi
	
	//////////////////////////////////////////////////////////////////////////////
	
	
	
	//////////////////////////////////////////////////////////////////////////////
	
	//								PAYLOAD_IN REGS
	reg [9:0] payload_buffer[63:0]; // buffer pentru citirea payload-ului
	reg [7:0] operands_addr[63:0]; //buffer pentru decodificarea payload-ului, aici 
	//pot fi operanzi din adresare imediata sau din adrese de memorie.
	
	reg [1:0] mod; // modul adresarii
	
	//////////////////////////////////////////////////////////////////////////////
	
		
		
	//////////////////////////////////////////////////////////////////////////////
	
	//								DATA_OUT REGS
	reg valid_out_reg; //valid out de tip reg pentru a lucra cu ele in combinational
	reg cmd_out_reg; // cmd out de tip reg pentru combinational
	reg [15:0] data_out_reg; // data out de tip reg pentru combinational
	
	//////////////////////////////////////////////////////////////////////////////
	
	
	
	
	//////////////////////////////////////////////////////////////////////////////
	
	//								OTHER REGS						
	reg boolean_error; //boolean pentru erori intalnite(nof_operands ==0 && 
	//	&& amm_response != 2'b00); 1 pentru true si 0 pt false
	reg [6:0] i; //index pentru for folosit la initializare vectori;
	
	//////////////////////////////////////////////////////////////////////////////
	
	
	// atribui output-ului datele din combinational
	assign data_out = data_out_reg; 
	assign valid_out = valid_out_reg;
	assign cmd_out = cmd_out_reg;
	
	
	
	// FSM - sequential part
	always@(posedge clk) begin
	
		 state <= state_next; //starile automatului
		 counter <= counter_next; //index pentru payload_buffer
		 sum <= sum_next; //in sum calculez suma pentru ADD
		 result <= result_next; // in rezultat calculez operatiile 1-9;
		 counter_decod <= counter_decod_next; //counter pentru decodificare
		 
		 if(rst_n == 0) begin
			  state <= `reset;
		 end
	 end
	
	always@(*) begin
		
		case(state)
			
			`reset: begin // in reset initializez orice reg pe care il folosesc cu 0 
			
				
				for(i = 0; i <= 63; i = i + 1)
					payload_buffer[i] = 10'b0;
				for(i = 0; i <= 63; i = i + 1)
					operands_addr[i] = 8'b0;
				
				nof_operands_header = 6'b0;
				opcode = 0;
				header = 0;
				
				amm_address = 0;
				amm_read = 0;
				boolean_error = 0;
				
				data_out_reg = 0;
				valid_out_reg = 0;
				cmd_out_reg= 0;
				
				
				sum_next = 12'b0;
				counter_next = 6'b0;
				mod = 2'b00;
				result_next = 8'b0;
				counter_decod_next = 6'b0;
				
				state_next = `read_header;
				
			end
			
			/*Mother duck as header
				
						  ,----,
					___.`      `,
					`===  D     :
					  `'.      .'
						  )    (                   ,
						 /      \_________________/|
						/                          |
					  |                           ;
					  |               _____       /
					  |      \       ______7    ,'
					  |       \    ______7     /
						\       `-,____7      ,'   
				^~^~^~^`\                  /~^~^~^~^
				  ~^~^~^ `----------------' ~^~^~^
				 ~^~^~^~^~^^~^~^~^~^~^~^~^~^~^~^~
			*/
			
			
			`read_header: begin //citesc date doar pentru header
				if(valid_in == 1 && cmd_in == 1) begin //protocol header
				
					header = data_in; //citesc date pentru header
					opcode = header[11:8]; //codul operatiei din header
					nof_operands_header = header[5:0]; //numar de operanzi
					
					if(nof_operands_header == 0) begin //caz de eroare
						boolean_error = 1; // eroare = true
						state_next = `generate_output_header; //fac trecerea la output, nu am date de preluat din payload;
					end
					
					else 
						state_next = `read_payload; //am numar nenul de operanzi, in starea urmatoare citesc payload-uri
				end
			   else if(valid_in == 0)
					state_next = `read_header; //daca valid_in == 0 trec la urmatorul clk pentru a citi alte date pentru header
				
			end
	
			/* Baby ducks as payloads
			

					_          _          _          _          _
				 >(')____,  >(')____,  >(')____,  >(')____,  >(') ___,
					(` =~~/    (` =~~/    (` =~~/    (` =~~/    (` =~~/
			~^~^`---'~^~^~^`---'~^~^~^`---'~^~^~^`---'~^~^~^`---'~^~^~

			*/
	
			`read_payload: begin  
			//execut operatii de citire pentru payload cat timp nr acestora este egal cu numarul de operanzi din header
				if(valid_in == 1 && cmd_in == 0) begin //protocol payload
						payload_buffer[counter_next] = data_in[9:0]; //adaug date in buffer, am nevoie de mod si operand/adresa
						 
						if(counter == nof_operands_header - 1) begin //nu mai am payload-uri de citit
							state_next = `decode_operand; //trec la starea de decodificare
							counter_next = 0; // resetez counter_next
						end
						else begin
							counter_next = counter + 1; //mai am de citit, maresc index pentru o noua atribuire
							state_next = `read_payload; // ma intorc in starea de citire
						end
					//lucrez cu counter_next la atribuiri pentru ca am nevoie sa introduc valori in index diferit, in cazul
					//in care folosesc counter la index = 0 peste valoarea din 0 o pune pe cea din 1 si tot asa
					//lucrez cu counter la conditii in situatia in care resetez counter_next cu 0
				end
			
				
			end
				
			`decode_operand: begin
			//decodific pentru fiecare element din payload_in
				if(counter_decod < nof_operands_header) begin // mai am payload-uri de decodificat
					mod = payload_buffer[counter_decod_next][9:8]; //salvez modul
					if(mod == 2'b00) begin //adresare imediata
						
						operands_addr[counter_decod_next] = payload_buffer[counter_decod_next][7:0]; //introduc valori in buffer
						
						//verific numarul de payload-uri cu nof_operands_header
						//--------------------------------------------------------------------------------------------------
						if(counter_decod < nof_operands_header - 1) begin //verific daca nu am ajuns la finalul buffer-ului
							counter_decod_next = counter_decod + 1;
							state_next = `decode_operand; // ma intorc in decodificare
						end
						
						if(counter_decod ==  nof_operands_header -1) begin //am iesit din vectorului
							counter_next = 0;
							state_next = `execute; // incep calculul operatiilor
						end
						//---------------------------------------------------------------------------------------------------
						
					  
					end
					if (mod == 2'b01) begin //adresare indirecta
						amm_read = 1; //incep operatia de citire din memorie
						amm_address = payload_buffer[counter_decod_next][7:0]; //atribui adresei din memorie valoarea din buffer
						if(amm_waitrequest) 
							state_next = `decode_amm; //trec in starea de decodificarea a memoriei
					end
				
				end
				else if(counter_decod ==  nof_operands_header - 1) begin //nu mai am elemente in buffer
					state_next = `execute; //calcul operatii
					counter_next = 0; //initializez counter_next cu 0 pentru a-l folosi la operatii
				end
			
			end
				
			`decode_amm: begin //stare in care lucrez doar cu memoria
				
				if(amm_waitrequest) begin
					state_next = `decode_amm; //trec in aceeasi stare pentru a astepta un ciclu de ceas pana cand este nevoie
				end
				
				//s-a incheiat asteptarea 
				else begin 
				
					if(amm_response == 0) //daca exista date valide in memorie
						operands_addr[counter_decod_next] = amm_readdata[7:0];// preiau datele din memorie					
					
					else
						boolean_error = 1; //caz de eroare
					
					
					
					amm_read = 0; //pun 0 pentru a incheia procesul de citire din memorie
					
					if(boolean_error == 1) 
						state_next = `generate_output_header; //ies din decode oriunde as fi in buffer pentru a scrie eroarea
						// deoarece nu are rost sa raman in `decode_payload
						
					
					//verific numarul de payload-uri cu nof_operands_header					
					//---------------------------------------------------------------------------------------------------
					else if(counter_decod < nof_operands_header - 1) begin
						state_next = `decode_operand;
						counter_decod_next = counter_decod + 1;
					end
					
					else if(counter_decod == nof_operands_header - 1) begin
						state_next = `execute;
						counter_next = 0;
					end
					//---------------------------------------------------------------------------------------------------
				
				
				end
				
			end
				
						
			`execute: begin // implementarea operatilor necesare pt alu
				
				case(opcode)
					//la fiecare operatie verific daca mai valori in operand pentru a lucra cu ele
					
					
					
					//operatii cu un singur operand
					//----------------------------------------------------------------------------
					`NOT: begin
						if(nof_operands_header == 1)
							result_next = ~operands_addr[0]; 
						else 
							boolean_error = 1;
					end
					
					`INC:	begin
						if(nof_operands_header == 1)
							result_next = operands_addr[0] + 1; 
						else 
							boolean_error = 1;
					end
					
					`DEC: begin
						if(nof_operands_header == 1)
							result_next = operands_addr[0] - 1;
						else 
							boolean_error = 1;
					end
					
					`NEG: begin
						if(nof_operands_header == 1)
							result_next = -operands_addr[0];
						else 
							boolean_error = 1;
					end
					//--------------------------------------------------------------------------------
					
					
					//operatii cu 2 operanzi
					//'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
					`SHL: begin
						if(nof_operands_header == 2)
							result_next = (operands_addr[0] << operands_addr[1]);
						else 
							boolean_error = 1;
					end
					
					`SHR: begin
						if(nof_operands_header == 2)
							result_next = (operands_addr[0] >> operands_addr[1]);
						else 
							boolean_error = 1;
					end
					//'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
					
					
					
					//operatii cu mai multi operanzi
					//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
					`ADD: begin
						if(counter < nof_operands_header) begin 
							sum_next = sum + operands_addr[counter]; //suma dintre suma precedenta si operand
						end
					end
					
					`AND: begin
						if(counter < nof_operands_header) begin
							if(counter == 0) //daca am un singur operand
								result_next = operands_addr[0]; //resultatul e dat de primul element din operand
							else if(operands_addr[counter] != 0) 
								result_next = result_next & operands_addr[counter]; //pentru mai multi operanzi fac & intre rez precedent si operand		
							else if (operands_addr[counter] == 0)
								result_next = operands_addr[counter]; 
							//AND intre un operand si 0 e mereu 0, nu trebuie sa fac AND pentru 0 daca am mai multi operanzi
						end
					end
					
					`OR: begin
						if(counter < nof_operands_header) begin
							result_next = result | operands_addr[counter]; // or dintre rez precedent si operand
						end
					end
					
					`XOR: begin
						if(counter < nof_operands_header) begin
							if(nof_operands_header == 1) 
								result_next = operands_addr[counter]; //intoarc doar primul operand in cazul in care am doar un operand
							else
								result_next = result ^ operands_addr[counter]; // pentru mai multi operanzi fac ^ intre rez precedent si operand
						end
					end
					//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
					
						
				endcase
				
				
					counter_next = counter + 1;
				if(boolean_error == 1) //daca am intalnit eroarea ma duc in output
					state_next = `generate_output_header;
				else if(counter == nof_operands_header - 1) //daca nu mai am operanzi in vectorul meu operands_adr
					state_next = `generate_output_header;
				else
					state_next = `execute;//ma intorc in execute pentru ca mai am operanzi
			end
			
			`generate_output_header: begin //output pt headear
				valid_out_reg = 1;
				cmd_out_reg = 1;
				//pun valori pe out ca sa pot genera data_out
				//if(valid_out_reg == 1 && cmd_out_reg == 1) begin //protocol header 
					if(boolean_error == 1)
						data_out_reg[15:0] = {11'b0, 1'b1, opcode};//header eroare
					else 
						data_out_reg[15:0] = {11'b0, 1'b0, opcode};//header fara eroare
				//end	
				state_next = `generate_output_payload;//generez out pentru payload
				
			end
			
			`generate_output_payload: begin //output pt payload
				cmd_out_reg = 0;
				//pun valori pe out ca sa pot genera data_out;
				//if(valid_out_reg == 1 && cmd_out_reg == 0) begin //protocol payload
					if(boolean_error == 0) begin
						if(opcode == 0)
							data_out_reg[15:0] = {4'b0, sum_next};//daca am adunare, folosesc sum_next
						else
							data_out_reg[15:0] = {8'b0, result_next}; // daca am alte operatii, trimit result_next ca out;
					end
					else 
						data_out_reg[15:0] = {4'b0, 12'hBAD}; //payload eroare;
				//end
				
				state_next = `reset; //reinitializarea valorilor pentru urmatorul header
			end
		
		endcase
	end
endmodule


