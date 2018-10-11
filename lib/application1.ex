defmodule Application1 do
  use Application
  use Bitwise
  @m 10

  def get_sliced_hash(val) do
    {decimal_hash, _} =
      if is_integer(val) do
        :crypto.hash(:sha, Integer.to_string(val)) |> Base.encode16() |> Integer.parse(16)
      else
        :crypto.hash(:sha, val) |> Base.encode16() |> Integer.parse(16)
      end

    sliced_hash =
      decimal_hash |> Integer.to_string(2) |> String.slice(0, @m) |> String.to_integer(2)
  end

  def find_finger(n, node_values) do
    if n in node_values do
      n
    else
      find_finger(rem(n + 1, trunc(:math.pow(2, @m))), node_values)
    end
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
          {DosProj3, [String.to_atom("#{sliced_hash}")]},
          id: String.to_atom("#{sliced_hash}")
        )
      end)

    opts = [strategy: :one_for_one, name: Supervisor]
    {:ok, supervisor} = Supervisor.start_link(children, opts)

    lst =
      Supervisor.which_children(supervisor)
      |> Enum.map(fn x -> elem(x, 0) end)
      |> Enum.map(fn x -> Atom.to_string(x) end)
      |> Enum.map(fn x -> String.to_integer(x) end)
      |> Enum.sort()
      |> Enum.map(fn x -> Integer.to_string(x) end)
      |> Enum.map(fn x -> String.to_atom(x) end)

    # list to hold node values for find_successor, closest_preceding_node functions
    node_values =
      lst
      |> Enum.map(fn x -> Atom.to_string(x) end)
      |> Enum.map(fn x -> String.to_integer(x) end)
      |> IO.inspect()

    r = trunc(:math.log2(num_of_nodes)) * 2

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

    0..(num_of_nodes - 1)
    |> Enum.to_list()
    |> Enum.map(fn x ->
      finger_table =
        0..(@m - 1)
        |> Enum.to_list()
        |> Enum.map(fn i ->
          # value_to_find = rem((Enum.at(node_values, x) + trunc(:math.pow(2, i))), trunc(:math.pow(2, @m)))
          value_to_find = rem(Enum.at(node_values, x) + (1 <<< i), 1 <<< @m)
          find_finger(value_to_find, node_values)
        end)

      GenServer.cast(Enum.at(lst, x), {:set_finger_table, finger_table})
    end)

    1..num_of_messages
    |> Enum.to_list()
    |> Enum.each(fn x -> make_file([Integer.to_string(x) <> ".mp3"], node_values) end)

    make_file(["abc.mp3"], node_values)

    :timer.sleep(5000)
    # Check states
    lst
    |> Enum.each(fn x -> GenServer.cast(x, {:print_state}) end)

    # GenServer.cast(Enum.at(lst, 0),  {:search, ["abc.mp3", get_sliced_hash("abc.mp3"), 0]})
  end

  def make_file(file_name, node_values) do
    sliced_hash = get_sliced_hash(file_name)

    # value_to_find = rem(sliced_hash, trunc(:math.pow(2, @m)))
    value_to_find = rem(sliced_hash, 1 <<< @m)

    node_as_integer = find_finger(value_to_find, node_values)
    node_as_atom = node_as_integer |> Integer.to_string() |> String.to_atom()

    GenServer.cast(node_as_atom, {:store_file, file_name})
  end
end
