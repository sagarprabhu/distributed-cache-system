defmodule Application1 do
  use Application
  @m 10
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
        {decimal_hash, _} =
          :crypto.hash(:sha, Integer.to_string(x)) |> Base.encode16() |> Integer.parse(16)

        sliced_hash =
          decimal_hash |> Integer.to_string(2) |> String.slice(0, @m) |> String.to_integer(2)

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
        |> Enum.sort
        |> Enum.map(fn x -> Integer.to_string(x) end)
        |> Enum.map(fn x -> String.to_atom(x) end)
    
    # list to hold node values for find_successor, closest_preceding_node functions
    node_values =
      lst
      |> Enum.map(fn x -> Atom.to_string(x) end)
      |> Enum.map(fn x -> String.to_integer(x) end)  
      |> IO.inspect
      
    r = trunc(:math.log2(num_of_nodes)) 

    0..(num_of_nodes - 1)
      |> Enum.to_list
      |> Enum.each(fn x -> 

        successors =
          1..r
            |> Enum.to_list()
            |> Enum.map(
              fn curr_r ->
                Enum.at(lst, rem(x + curr_r, num_of_nodes))
              end    
            )

        GenServer.cast(
          Enum.at(lst, x),
          {:set_neighbours, [Enum.at(lst, x-1)] ++ successors}
        )
      end)
    
    # 0..(num_of_nodes - 1)
    #   |> Enum.to_list
    #   |> Enum.each(
    #     fn x ->
    #       finger_table =
    #         1..r
    #           |> Enum.to_list
    #           |> Enum.map(find)
    #     end
    #   )
  end
end
