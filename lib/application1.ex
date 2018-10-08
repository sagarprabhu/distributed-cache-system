defmodule Application1 do
    use Application
    @m 100
    def main(args \\ []) do
        
        Application1.start(:abc, String.to_integer(Enum.at(args, 0)), String.to_integer(Enum.at(args, 1)))

        # receive do
        #     {:hi, message} -> IO.puts message
        # end
    end

    def start(_type, num_of_nodes, num_of_messages) do
    children =
      1..num_of_nodes
      |> Enum.to_list()
      |> Enum.map(fn x ->
        {sliced_hash, _} = :crypto.hash(:sha, Integer.to_string(x)) |> Base.encode16 |> String.slice(0, @m) |> Integer.parse(16)

        IO.inspect sliced_hash
        
        Supervisor.child_spec(
          {DosProj3, [String.to_atom("N#{sliced_hash}")]},
          id: String.to_atom("N#{sliced_hash}")
        )
      end)
     opts = [strategy: :one_for_one, name: Supervisor]
    {:ok, supervisor} = Supervisor.start_link(children, opts)
     Supervisor.which_children(supervisor)
  end
end