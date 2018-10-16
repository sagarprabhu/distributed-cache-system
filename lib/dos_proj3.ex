defmodule DosProj3 do
  use GenServer

  # External API
  def start_link([input_name, node_value]) do
    GenServer.start_link(
      __MODULE__,
      %{
        :finger_table => [],
        :predecessor => [],
        :successor => [],
        :local_file => [],
        :current_value => node_value
      },
      name: input_name
    )
  end

  # Genserver Implementation
  def init(initial_map) do
    {:ok, initial_map}
  end

  # Neighbours
  def handle_cast({:set_neighbours, list_neighbours}, current_map) do
    [input_predecessor | input_successors] = list_neighbours

    {_, updated_map} =
      Map.get_and_update(current_map, :predecessor, fn x -> {x, x ++ input_predecessor} end)

    {_, updated_map} =
      Map.get_and_update(updated_map, :successor, fn x -> {x, x ++ input_successors} end)

    {:noreply, updated_map}
  end

  # Finger table
  def handle_cast({:set_finger_table, finger_table}, current_map) do
    {_, updated_map} =
      Map.get_and_update(current_map, :finger_table, fn x -> {x, x ++ finger_table} end)

    {:noreply, updated_map}
  end

  # Store file
  def handle_cast({:store_file, file_name}, current_map) do
    {_, updated_map} =
      Map.get_and_update(current_map, :local_file, fn x -> {x, x ++ file_name} end)

    # Send the file to predecessor for failure handling and load balance
    GenServer.cast(
      updated_map.predecessor |> Integer.to_string() |> String.to_atom(),
      {:store_file_as_backup, file_name}
    )

    # Send the file to the successor for failure handling and load balance
    GenServer.cast(
      List.first(updated_map.successor) |> Integer.to_string() |> String.to_atom(),
      {:store_file_as_backup, file_name}
    )

    {:noreply, updated_map}
  end

  # Store files in the successor and predecessors using this function rather than {:store_file, file_name}
  def handle_cast({:store_file_as_backup, file_name}, current_map) do
    {_, updated_map} =
      Map.get_and_update(current_map, :local_file, fn x -> {x, x ++ file_name} end)

    {:noreply, updated_map}
  end

  # Print states for debugging
  def handle_cast({:print_state}, current_map) do
    IO.inspect(current_map)
    {:noreply, current_map}
  end

  # Search for file by file_name
  def handle_cast({:search, [file_name, key, hops_taken]}, current_map) do
    IO.inspect(current_map)

    is_file_found = Enum.member?(current_map.local_file, file_name)

    # IO.inspect is_file_found

    if not is_file_found do

      # Check for the wrap around
      if key > current_map.current_value and Enum.at(current_map.successor, 0) < current_map.current_value do
        # If this is the last node and the key is more than it, send the request to the first node.
        node_to_send_to = Enum.at(current_map.successor, 0)
        
        GenServer.cast(
          node_to_send_to |> Integer.to_string() |> String.to_atom(),
          {:search, [file_name, key, hops_taken + 1]}
        )
      
      else
        # Send request to the closest node in the finger table which is <= key
        node_to_send_to =
          current_map.finger_table
          |> Enum.filter(fn x -> x <= key end)
          |> Enum.min_by(fn x -> key - x end, fn -> nil end)

        # |> Enum.max()
        # |> List.last

        # If no node <= key exists then send request to the successor
        node_to_send_to =
          if node_to_send_to == nil, do: Enum.at(current_map.successor, 0), else: node_to_send_to

        # IO.inspect node_to_send_to
        GenServer.cast(
          node_to_send_to |> Integer.to_string() |> String.to_atom(),
          {:search, [file_name, key, hops_taken + 1]}
        ) 
      end 
    else
      IO.puts("File found in #{hops_taken} hops")
    end

    {:noreply, current_map}
  end
end
