defmodule Application1 do
  use Application
  use Bitwise
  @m 10

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

  # Add new node to the chord supervised by supervisor
  # The value of the node should be <= 2^m
  def add_node(supervisor, node_value) when node_value < 1 <<< @m do
    Supervisor.start_child(
      supervisor,
      Supervisor.child_spec(
        {DosProj3, [String.to_atom("#{node_value}"), node_value]},
        id: String.to_atom("#{node_value}")
      )
    )

    # Check the new supervisor children list
    IO.inspect(Supervisor.which_children(supervisor))
  end

  # Search for file file_name
  # A list of all chord nodes has to be passed(Nodes as atoms not node_values)
  def search(lst_of_chord_nodes, file_name) when is_binary(file_name) do
    GenServer.cast(
      Enum.at(lst_of_chord_nodes, 0),
      {:search, [file_name, get_sliced_hash(file_name), 0]}
    )
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

  def start(_type, num_of_nodes, num_of_messages) do
    children =
      1..num_of_nodes
      |> Enum.to_list()
      |> Enum.map(fn x ->
        sliced_hash = get_sliced_hash(x)

        Supervisor.child_spec(
          {DosProj3, [String.to_atom("#{sliced_hash}"), sliced_hash]},
          id: String.to_atom("#{sliced_hash}")
        )
      end)

    opts = [strategy: :one_for_one, name: Supervisor]
    {:ok, supervisor} = Supervisor.start_link(children, opts)

    # List of all Nodes in a sorted order
    # Need sorting to maintain order in the ring
    lst =
      Supervisor.which_children(supervisor)
      |> Enum.map(fn x -> elem(x, 0) end)
      |> Enum.map(fn x -> Atom.to_string(x) end)
      |> Enum.map(fn x -> String.to_integer(x) end)
      |> Enum.sort()
      |> Enum.map(fn x -> Integer.to_string(x) end)
      |> Enum.map(fn x -> String.to_atom(x) end)
      |> IO.inspect()

    # list to hold node values as integers for find_successor, closest_preceding_node functions
    node_values =
      lst
      |> Enum.map(fn x -> Atom.to_string(x) end)
      |> Enum.map(fn x -> String.to_integer(x) end)
      |> IO.inspect()

    # Number of successors for failure handling(r) = 2 * log n 
    r = trunc(:math.log2(num_of_nodes)) * 2

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

    #  Store files from 0.mp3 to <num_of_messages>.mp3
    #  The nodes will fetch every file once
    1..num_of_messages
    |> Enum.to_list()
    |> Enum.each(fn x -> make_file([Integer.to_string(x) <> ".mp3"], node_values) end)

    make_file(["abc.mp3"], node_values)
    make_file(["test"], node_values)

    # # Check states for Debugging
    # :timer.sleep(5000)
    # lst
    # |> Enum.each(fn x -> GenServer.cast(x, {:print_state}) end)

    # Search for file
    GenServer.cast(Enum.at(lst, 0), {:search, ["abc.mp3", get_sliced_hash("abc.mp3"), 0]})
    search(lst, "test")

    add_node(supervisor, 50)
  end
end
