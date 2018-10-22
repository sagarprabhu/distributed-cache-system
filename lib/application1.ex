defmodule Application1 do
  use Application
  use Bitwise
  @m 21

  # Function to get a sliced hash value based on @m
  # Will take both Integers and Strings and return an integer value of sliced hash
  def get_sliced_hash(val) do
    {decimal_hash, _} =
      if is_integer(val) do
        :crypto.hash(:sha, Integer.to_string(val)) |> Base.encode16() |> Integer.parse(16)
      else
        :crypto.hash(:sha, val) |> Base.encode16() |> Integer.parse(16)
      end

    # Convert to binary and then slice and then convert back to integer.
    sliced_hash =
      decimal_hash |> Integer.to_string(2) |> String.slice(0, @m) |> String.to_integer(2)
  end

  # Finds an entry for the finger table based on node_values recursively
  # Should not return own_value
  def find_finger(own_value, n, node_values) do
    if n in node_values and n != own_value do
      n
    else
      find_finger(own_value, rem(n + 1, 1 <<< @m), node_values)
    end
  end

  # Finds the immediate successor for n in node_values
  # The value of the node should be <= 2^m
  # This works like find_finger
  def find_immediate_successor(n, node_values) when n < 1 <<< @m do
    # # Recursive way
    # if n in node_values, do: n, else: find_immediate_successor(rem(n + 1, 1 <<< @m), node_values)

    # Non-recursive way (using filter and min_by)
    if n > Enum.at(node_values, -1) do
      Enum.at(node_values, 0)
    else
      node_values
      |> Enum.filter(fn x -> x > n end)
      |> Enum.min_by(fn x -> x - n end, fn -> nil end)
    end
  end

  # Function to store a file in the network
  def make_file(file_name, node_values) do
    # Get key using the same logic as for nodes
    sliced_hash = get_sliced_hash(file_name)

    # value_to_find = key % 2^m 
    value_to_find = rem(sliced_hash, 1 <<< @m)

    # Don't need to pass own_value for files
    node_as_integer = find_finger(:garbage, value_to_find, node_values)
    node_as_atom = node_as_integer |> Integer.to_string() |> String.to_atom()

    # Store file at node
    GenServer.cast(node_as_atom, {:store_file, file_name})
  end

  # Add new node to the chord supervised by supervisor and return Sorted Node List
  # The value of the node should be <= 2^m
  def add_node(supervisor, n, pid2) when n < 1 <<< @m do
    # Increase the number of nodes global counter
    global_num_of_nodes = :ets.lookup_element(:global_values, :num_of_nodes, 2)
    :ets.insert(:global_values, {:num_of_nodes, global_num_of_nodes + 1})
    ip_node_as_atom = n |> Integer.to_string() |> String.to_atom()

    # Add this node to the chord supervisor
    Supervisor.start_child(
      supervisor,
      Supervisor.child_spec(
        {DosProj3, [String.to_atom("#{n}"), n, pid2]},
        id: String.to_atom("#{n}")
      )
    )

    # Check the new supervisor children list
    IO.inspect(Supervisor.which_children(supervisor))

    # sorted node values
    node_values = get_sorted_nodes(supervisor) |> get_values_from_atoms

    # Get successor and predecessor
    immediate_successor_integer = find_immediate_successor(n, node_values)

    immediate_successor_atom =
      immediate_successor_integer |> Integer.to_string() |> String.to_atom()

    successors_predecessor_integer = GenServer.call(immediate_successor_atom, :get_predecessor)
    IO.inspect("test #{successors_predecessor_integer}")

    successors_predecessor_atom =
      successors_predecessor_integer |> Integer.to_string() |> String.to_atom()

    # Set predecessors
    GenServer.cast(immediate_successor_atom, {:set_predecessor, n})
    GenServer.cast(ip_node_as_atom, {:set_predecessor, successors_predecessor_integer})

    # Set successors
    GenServer.cast(successors_predecessor_atom, {:set_successor, n})
    GenServer.cast(ip_node_as_atom, {:set_successor, immediate_successor_integer})

    # Set current nodes successors as list of successors of the next node
    successors_successor_list = GenServer.call(immediate_successor_atom, :get_successor_list)
    GenServer.cast(ip_node_as_atom, {:set_successor_list, successors_successor_list})

    # Get successors finger table
    successors_finger_table = GenServer.call(immediate_successor_atom, :get_finger_table)
    # set current nodes finger table
    GenServer.cast(ip_node_as_atom, {:set_finger_table, successors_finger_table})

    # Fix fingers and start the scheduled process
    Kernel.send(ip_node_as_atom, :fix_finger_table)

    # Get successors local files
    successors_local_files = GenServer.call(immediate_successor_atom, :get_files)

    files_to_store =
      successors_local_files
      |> Enum.filter(fn x ->
        get_sliced_hash(x) > successors_predecessor_integer and get_sliced_hash(x) <= n
      end)

    # Store files
    GenServer.cast(ip_node_as_atom, {:store_file_as_backup, files_to_store})

    # Print state for debugging
    GenServer.cast(ip_node_as_atom, {:print_state})
  end

  # Search for files from 1..num_of_messages.mp3
  # A list of all chord nodes has to be passed(Nodes as atoms not node_values)
  def search(lst, num_of_messages) do
    lst = lst |> Enum.filter(fn x -> Process.whereis(x) != nil end)
    node_values = get_values_from_atoms(lst)

    # # Initialize ets for each node
    # node_values 
    #   |> Enum.each(fn x -> :ets.insert(:global_values, {x, 0}) end)

    # Set a global counter for number of nodes
    :ets.insert(:global_values, {:counter_remaining_nodes, length(lst)})
    :ets.insert(:global_values, {:total_num_of_hops, 0})

    # Start periodic process for search at every node
    0..(length(lst) - 1)
    |> Enum.to_list()
    |> Enum.each(fn x ->
      Process.send_after(Enum.at(lst, x), {:start_search, num_of_messages, 1}, 0)
    end)
  end

  # Return list of all nodes of the supervisor in sorted order in Atom form
  def get_sorted_nodes(supervisor) do
    Supervisor.which_children(supervisor)
    |> Enum.map(fn x -> elem(x, 0) end)
    |> Enum.map(fn x -> Atom.to_string(x) end)
    |> Enum.map(fn x -> String.to_integer(x) end)
    |> Enum.sort()
    |> Enum.map(fn x -> Integer.to_string(x) end)
    |> Enum.map(fn x -> String.to_atom(x) end)
  end

  def get_values_from_atoms(lst) do
    lst
    |> Enum.map(fn x -> Atom.to_string(x) end)
    |> Enum.map(fn x -> String.to_integer(x) end)
  end

  def main(args \\ []) do
    Application1.start(
      :abc,
      String.to_integer(Enum.at(args, 0)),
      String.to_integer(Enum.at(args, 1))
    )

    # receive do
    #     {:hi, message} -> IO.puts message
    # end
  end

  def fail_node(lst) do
    # Decrease the number of nodes global counter
    global_num_of_nodes = :ets.lookup_element(:global_values, :num_of_nodes, 2)
    :ets.insert(:global_values, {:num_of_nodes, global_num_of_nodes + 1})

    send(Process.whereis(Enum.at(lst, 0)), :kill)
    IO.inspect("Failing Node #{Enum.at(lst, 0)}")
  end

  def start(_type, num_of_nodes, num_of_messages) do
    # Create new table named global values for storing the number of nodes
    :ets.new(:global_values, [:named_table])
    :ets.insert(:global_values, {:num_of_nodes, num_of_nodes})
    {_, pid2} = Task.start_link(__MODULE__, :counter, [num_of_nodes, 0, self(), num_of_nodes])

    children =
      0..(num_of_nodes - 1)
      |> Enum.to_list()
      |> Enum.map(fn x ->
        sliced_hash = get_sliced_hash(x)

        Supervisor.child_spec(
          {DosProj3, [String.to_atom("#{sliced_hash}"), sliced_hash, pid2]},
          id: String.to_atom("#{sliced_hash}")
        )
      end)

    opts = [strategy: :one_for_one, name: Supervisor]
    {:ok, supervisor} = Supervisor.start_link(children, opts)

    # List of all Nodes in a sorted order
    # Need sorting to maintain order in the ring
    lst = get_sorted_nodes(supervisor) |> IO.inspect()

    # list to hold node values as integers for find_successor, closest_preceding_node functions
    node_values = get_values_from_atoms(lst) |> IO.inspect()

    # Number of successors for failure handling(r) = 2 * log n 
    r = trunc(:math.log2(10)) * 2

    # Set neighbours
    0..(num_of_nodes - 1)
    |> Enum.to_list()
    |> Enum.each(fn x ->
      successors =
        1..r
        |> Enum.to_list()
        |> Enum.map(fn curr_r ->
          Enum.at(lst, rem(x + curr_r, num_of_nodes))
        end)
        |> Enum.map(fn x -> Atom.to_string(x) end)
        |> Enum.map(fn x -> String.to_integer(x) end)

      GenServer.cast(
        Enum.at(lst, x),
        {:set_neighbours,
         [Enum.at(lst, x - 1) |> Atom.to_string() |> String.to_integer()] ++ successors}
      )
    end)

    # Set finger tables
    0..(num_of_nodes - 1)
    |> Enum.to_list()
    |> Enum.map(fn x ->
      finger_table =
        0..(@m - 1)
        |> Enum.to_list()
        |> Enum.map(fn i ->
          value_to_find = rem(Enum.at(node_values, x) + (1 <<< i), 1 <<< @m)
          find_finger(Enum.at(node_values, x), value_to_find, node_values)
        end)

      GenServer.cast(Enum.at(lst, x), {:set_finger_table, finger_table})
    end)

    # if num_of_nodes>10 do
    #   11..num_of_nodes
    #   |> Enum.to_list()
    #   |> Enum.map( fn x ->
    #     :timer.sleep(750)
    #     add_node(supervisor,get_sliced_hash(x),pid2)
    #   end
    #   )
    # end 

    # lst = get_sorted_nodes(supervisor)
    # # list to hold node values as integers for find_successor, closest_preceding_node functions
    # node_values = get_values_from_atoms(lst) 

    # IO.inspect("node values final #{lst}")
    :timer.sleep(1000)

    #  Store files from 0.mp3 to <num_of_messages>.mp3
    #  The nodes will fetch every file once
    1..num_of_messages
    |> Enum.to_list()
    |> Enum.each(fn x -> make_file([Integer.to_string(x) <> ".mp3"], node_values) end)

    # make_file(["abc.mp3"], node_values)
    # make_file(["test"], node_values)

    # lst
    # |> Enum.each(fn x -> GenServer.cast(x, {:print_state}) end)

    # # Search for file
    # GenServer.cast(Enum.at(lst, 0), {:search, ["abc.mp3", get_sliced_hash("abc.mp3"), 0]})
    # search(lst, "test")

    # add_node(supervisor, 774,pid2)
    # # add_node(supervisor, 950,pid2)
    # add_node(supervisor, 951,pid2)
    # add_node(supervisor, 952,pid2)

    # lst = lst |> Enum.filter(fn x -> Process.whereis(x) != nil end)
    # node_values = get_values_from_atoms(lst)

    # Start periodic process for search at every node
    search(lst, num_of_messages)

    receive do
      {:finished, sum} ->
        IO.inspect("Job1 Avg=#{sum / (num_of_nodes * num_of_messages)}")
    end

    # Start scheduled process for fix_finger_table
    # 0..(num_of_nodes - 1)
    #   |> Enum.to_list()
    #   |> Enum.each(fn x ->  Process.send_after(Enum.at(lst, x), :fix_finger_table, 1_000) end)
    # fail 576
    # :timer.sleep(20000)
    fail_node(lst)

    lst = lst |> Enum.filter(fn x -> Process.whereis(x) != nil end)
    node_values = get_values_from_atoms(lst)

    search(lst, num_of_messages)

    receive do
      {:finished, sum} ->
        IO.inspect("Job2 Avg=#{sum / ((num_of_nodes - 1) * num_of_messages)}")
    end
  end

  # function to count average no. of hops
  def counter(count, sum, pid, num_of_nodes) do
    receive do
      # pattern matching for each successful lookup
      {:hello, hops} ->
        sum = sum + hops
        counter(count, sum, pid, num_of_nodes)

      # pattern matching for counting number of nodes
      {:hi, msg} ->
        count = count - 1

        if count <= 0 do
          send(pid, {:finished, sum})
          counter(num_of_nodes - 1, 0, pid, num_of_nodes)
        else
          counter(count, sum, pid, num_of_nodes)
        end
    end
  end
end
