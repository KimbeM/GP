class comb_circuit #(parameter NUM_INPUTS, NUM_ROWS, NUM_COLS, LEVELS_BACK, NUM_MUTAT);
  typedef enum integer {WIRE = 0, NOT = 1, AND = 2, OR = 3, XOR = 4} t_operation;
  int         arity_lut[5] = {1, 1, 2, 2, 2};  //Arity look-up table for "t_operation" typedef
  int         node_arity[NUM_INPUTS + NUM_ROWS * NUM_COLS];
  t_operation func_gene[NUM_ROWS * NUM_COLS];
  int         conn_gene[NUM_ROWS * NUM_COLS][];
  bit         eval_outputs[NUM_INPUTS + NUM_ROWS * NUM_COLS];
  int         conn_output;

  function new();
  
    create_func_gene();
    
    create_conn_gene();
  
  endfunction: new
  
  function comb_circuit copy();
    copy = new();
    copy.arity_lut    = this.arity_lut;
    copy.node_arity   = this.node_arity;
    copy.func_gene    = this.func_gene;
    copy.conn_gene    = this.conn_gene;
    copy.eval_outputs = this.eval_outputs;
    copy.conn_output  = this.conn_output;
    return copy;
  endfunction  
  
  function create_func_gene();
    //Randomize operation for each node
    for(int i=0; i<NUM_ROWS * NUM_COLS; i++)begin
      func_gene[i] = t_operation'($urandom_range(0,4));
    end  
  endfunction: create_func_gene  
  
  function create_conn_gene();    
    t_operation node_op;
    int         conn;
    int         conn_prev;

    //Arity for column 0 (=INPUTS) is one
    for(int i=0; i<NUM_INPUTS; i++)begin
      node_arity[i]   = 1;
    end 

    //Allocate connections according to node arity
    for(int i=0; i<NUM_ROWS * NUM_COLS; i++)begin
      node_op                    = func_gene[i];
      node_arity[i+NUM_INPUTS]   = arity_lut[int'(node_op)];
      conn_gene[i]               = new[node_arity[i+NUM_INPUTS]];
    end

    //Randomize connections for each node
    //If arity = 2, ensure that connections are from different nodes
    for(int i=0; i<NUM_ROWS; i++)begin
      for(int j=0; j<NUM_COLS; j++)begin
        for(int k=0; k<node_arity[NUM_INPUTS + i + (NUM_ROWS * j)]; k++)begin
          if(k == 1)
            conn_prev = conn;
          do begin
            if(j == 0)begin
              conn               = $urandom_range(0, NUM_INPUTS-1);
              conn_gene[i][k]    = conn;
            end else if(j < LEVELS_BACK)begin
              conn                             = $urandom_range(0, NUM_INPUTS+(j*NUM_ROWS)-1);
              conn_gene[i + (NUM_ROWS * j)][k] = conn;
            end else begin
              conn                             = $urandom_range(NUM_INPUTS+((j-LEVELS_BACK)*NUM_ROWS), NUM_INPUTS+(j*NUM_ROWS)-1);
              conn_gene[i + (NUM_ROWS * j)][k] = conn;
            end
          end while(conn == conn_prev && k == 1);
        end  
      end 
    end 
    
    //Randomize connection for output node
    conn_output = $urandom_range(NUM_INPUTS+((NUM_COLS-LEVELS_BACK)*NUM_ROWS), NUM_INPUTS+(NUM_COLS*NUM_ROWS)-1);
    
  endfunction: create_conn_gene  
  
  function bit evaluate_node_output(int idx);
    bit input_A;
    bit input_B;
    bit out;
    
    if(node_arity[idx] == 2)begin
      input_A = eval_outputs[conn_gene[idx - NUM_INPUTS][0]]; 
      input_B = eval_outputs[conn_gene[idx - NUM_INPUTS][1]];
      if(func_gene[idx - NUM_INPUTS] == AND)begin
        out   = input_A & input_B;
      end else if(func_gene[idx - NUM_INPUTS] == OR)begin
        out   = input_A | input_B;
      end else if(func_gene[idx - NUM_INPUTS] == XOR)begin
        out   = input_A ^ input_B;
      end
    end else begin
      input_A = eval_outputs[conn_gene[idx - NUM_INPUTS][0]]; 
      if(func_gene[idx - NUM_INPUTS] == WIRE)begin
        out   = input_A;
      end else if(func_gene[idx - NUM_INPUTS] == NOT) begin
        out   = ~input_A;
      end
    end    
    
    return out;
  endfunction: evaluate_node_output
  

  function bit evaluate_fitness(bit[NUM_INPUTS-1:0] inputs);
    bit out;
  
    //First column of eval_outputs = comb circuit input  
    for(int i=0; i<NUM_INPUTS; i++)begin
      eval_outputs[i] = inputs[i];
    end
    
    //Evaluate outputs for rest of comb circuit gate
    for(int i=NUM_INPUTS; i<NUM_ROWS * NUM_COLS + NUM_INPUTS; i++)begin
      eval_outputs[i] = evaluate_node_output(i);
      if(i == conn_output)begin
        out = eval_outputs[i];
        break;
      end
    end
  
    //Evaluate output of comb circuit
    return out;
  endfunction: evaluate_fitness 
  
  function int calc_num_gates();
    int         idx_q[$];            
    bit         tree[int][];         //For storing info about which nodes have been visited
    int         num_gates     = 0;  
    t_operation func          = func_gene[conn_output - NUM_INPUTS];     
    bit         tree_complete = 0;
    string      netlist[$];
    string      s;
    
    idx_q.push_front(conn_output);
    
    //Traverse comb_circuit backwards from its output to its input(s).
    //Only nodes that affect the output are added to the tree.
    //When all nodes have been added to the tree, exit this while-loop.
    while(~tree_complete)begin
      if(idx_q[0] >= NUM_INPUTS)begin
      
        //Function of the node currently pointed to
        func = func_gene[idx_q[0] - NUM_INPUTS];    
 
        //Allocate memory for the dynamic dimension of the tree according to the arity of the gate currently pointed to.
        //OBS: only if memory has not been allocated already for this node.
        if(tree[idx_q[0]].size() == 0)begin  
          if(arity_lut[int'(func)] == 1)begin
            tree[idx_q[0]]    = new[1];
            tree[idx_q[0]][0] = 0;
          end else begin
            tree[idx_q[0]] = new[2];
            foreach(tree[idx_q[0]][i])
              tree[idx_q[0]][i] = 0;
          end
        end
           
        //If unvisited nodes exist in the backward direction in the circuit, traverse backwards.
        //If all nodes in the backward direction from the current node have been visited,
        //traverse forwards in the circuit (towards output).
        if(tree[idx_q[0]][0] == 0)begin
          tree[idx_q[0]][0] = 1;
          if(func_gene[idx_q[0] - NUM_INPUTS] == NOT)begin
            s = "(";
            netlist.push_back(s);
            s = "NOT";
            netlist.push_back(s);
          end          
          idx_q.push_front(conn_gene[idx_q[0] - NUM_INPUTS][0]);
        end else if(tree[idx_q[0]].size() == 2 && tree[idx_q[0]][1] == 0)begin       
          tree[idx_q[0]][1] = 1;
          s = func_gene[idx_q[0] - NUM_INPUTS].name;
          netlist.push_back(s);          
          idx_q.push_front(conn_gene[idx_q[0] - NUM_INPUTS][1]); 
        end else begin
          if(idx_q[1] == conn_output && tree[idx_q[1]].and() == 1)
            tree_complete = 1;
          else
            idx_q.delete(0);
        end
      end else if(idx_q[0] < NUM_INPUTS)begin
        if(idx_q[1] == conn_output && tree[idx_q[1]].and() == 1)
            tree_complete = 1;
        else
          if(tree[idx_q[1]][1] == 0)begin
            s = "(";
            netlist.push_back(s);
            s.itoa(idx_q[0]);
            netlist.push_back(s);
          end else begin
            s.itoa(idx_q[0]);
            netlist.push_back(s);    
            s = ")";
            netlist.push_back(s);
          end
          idx_q.delete(0);
      end 
    end

    //Check all nodes present in tree. All functions except "wire" increase the gate count
    foreach(tree[i])begin
      if(func_gene[i - NUM_INPUTS] != WIRE)
        num_gates = num_gates + 1;
    end
    
    return num_gates;
  endfunction: calc_num_gates
  
  function mutate();
    int         mut_nodes[NUM_MUTAT];
    t_operation mut_func;
    int         conn;
    int         conn_prev;
    int         idx = 0;
  
    //Randomize which nodes get mutated
    for(int i=0; i<NUM_MUTAT; i++)begin
      mut_nodes[i] = $urandom_range(NUM_INPUTS, NUM_ROWS * NUM_COLS + NUM_INPUTS);
    end
  
    //Randomize functions for the chosen nodes
    for(int i=0; i<NUM_MUTAT; i++)begin
      func_gene[i - NUM_INPUTS] = t_operation'($urandom_range(0,4));
    end    
    
    //Randomize connections for mutation nodes
    //If arity = 2, ensure that connections are from different nodes
    for(int i=0; i<NUM_ROWS; i++)begin
      for(int j=0; j<NUM_COLS; j++)begin
        if(mut_nodes[idx] == NUM_INPUTS + i + (j * NUM_ROWS))begin
          idx = idx + 1;
          for(int k=0; k<node_arity[NUM_INPUTS + i + (NUM_ROWS * j)]; k++)begin
            if(k == 1)
              conn_prev = conn;
            do begin
              if(j == 0)begin
                conn               = $urandom_range(0, NUM_INPUTS-1);
                conn_gene[i][k]    = conn;
              end else if(j < LEVELS_BACK)begin
                conn                             = $urandom_range(0, NUM_INPUTS+(j*NUM_ROWS)-1);
                conn_gene[i + (NUM_ROWS * j)][k] = conn;
              end else begin
                conn                             = $urandom_range(NUM_INPUTS+((j-LEVELS_BACK)*NUM_ROWS), NUM_INPUTS+(j*NUM_ROWS)-1);
                conn_gene[i + (NUM_ROWS * j)][k] = conn;
              end
            end while(conn == conn_prev && k == 1);
          end
        end
          if(idx == NUM_MUTAT)
            break;
      end
        if(idx == NUM_MUTAT)
          break; 
    end
  
  endfunction: mutate
 
endclass: comb_circuit