defmodule DosProj3 do
  use GenServer, restart: :temporary
  use Bitwise

  # External API
  def start_link([input_name, node_value, pid]) do
    GenServer.start_link(
      __MODULE__,
      %{
        :finger_table => [],
        :predecessor => nil,
        :successor => [],
        :local_file => [],
        :current_value => node_value,
        :pid => pid
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
      Map.get_and_update(current_map, :predecessor, fn x -> {x, input_predecessor} end)

    {_, updated_map} =
      Map.get_and_update(updated_map, :successor, fn x -> {x, x ++ input_successors} end)

    {:noreply, updated_map}
  end

  # Sets finger table by appending 
  def handle_cast({:set_finger_table, finger_table}, current_map) do
    # Map.get_and_update(current_map, :finger_table, fn x -> {x, x ++ finger_table} end)
    {_, updated_map} =
      Map.get_and_update(current_map, :finger_table, fn x -> {x, finger_table} end)

    IO.inspect(updated_map)
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
    # IO.inspect(current_map)

    is_file_found = Enum.member?(current_map.local_file, file_name)

    # IO.inspect is_file_found
    # {_,updated_map}=
    if is_file_found do
      #   IO.puts("File found in #{hops_taken} hops")
      send(current_map.pid, {:hello, hops_taken})

      # IO.inspect(current_map.hops)
      # Map.get_and_update(current_map, :hops, fn x ->
      #     {x, hops_taken + x}
      #   end)
      # else
      #   {:hi,current_map} 
    end

    if not is_file_found do
      # Check for the wrap around
      if key > current_map.current_value and
           Enum.at(current_map.successor, 0) < current_map.current_value do
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

      # prev_val = :ets.lookup_element(:global_values, current_map.current_value, 2)
      # :ets.insert(:global_values, {current_map.current_value, prev_val + hops_taken})
    end

    {:noreply, current_map}
  end

  def handle_cast({:set_predecessor, node_to_set_as_predecessor}, current_map) do
    {_, updated_map} =
      Map.get_and_update(current_map, :predecessor, fn x -> {x, node_to_set_as_predecessor} end)

    IO.inspect(updated_map)

    {:noreply, updated_map}
  end

  def handle_cast({:set_successor, node_to_set_as_successor}, current_map) do
    num_of_nodes = :ets.lookup_element(:global_values, :num_of_nodes, 2)

    {_, updated_map} =
      if length(current_map.successor) >= trunc(:math.log2(num_of_nodes)) * 2 do
        Map.get_and_update(current_map, :successor, fn x ->
          {x, List.insert_at(x, 0, node_to_set_as_successor) |> List.delete_at(-1)}
        end)
      else
        Map.get_and_update(current_map, :successor, fn x ->
          {x, List.insert_at(x, 0, node_to_set_as_successor)}
        end)
      end

    IO.inspect(updated_map)

    {:noreply, updated_map}
  end

  def handle_cast({:set_successor_list, list_of_successors}, current_map) do
    num_of_nodes = :ets.lookup_element(:global_values, :num_of_nodes, 2)

    full_list = current_map.successor ++ list_of_successors

    sliced_list =
      if length(full_list) > trunc(:math.log2(num_of_nodes)) * 2 do
        Enum.slice(full_list, 0, trunc(:math.log2(num_of_nodes)) * 2)
      else
        full_list
      end

    {_, updated_map} = Map.get_and_update(current_map, :successor, fn x -> {x, sliced_list} end)

    {:noreply, updated_map}
  end

  # Start search for files from 1..num_of_files
  def handle_info({:start_search, num_of_files, current_file_index}, current_map) do
    # Stop if num_of_files have been searched
    if current_file_index <= num_of_files do
      file_to_search = Integer.to_string(current_file_index) <> ".mp3"

      GenServer.cast(
        self(),
        {:search, [file_to_search, Application1.get_sliced_hash(file_to_search), 0]}
      )

      # IO.inspect current_file_index
      periodic_search(num_of_files, current_file_index + 1)
    else
      IO.inspect("search finished for #{current_map.current_value}")
      send(current_map.pid, {:hi, "finished"})

      # send current_map.pid, {:hello , current_map.hops}
      # prev_val = :ets.lookup_element(:global_values, current_map.current_value, 2)
      # :ets.insert(:global_values, {current_map.current_value, current_map.hops_taken})

      # remaining_nodes = :ets.lookup_element(:global_values, :counter_remaining_nodes, 2)
      # remaining_nodes = remaining_nodes - 1
      # if remaining_nodes > 0 do
      #   :ets.insert(:global_values, {:counter_remaining_nodes, remaining_nodes})
      # else
      #   calculate_average()
      # end
    end

    {:noreply, current_map}
  end

  defp calculate_average() do
  end

  defp periodic_search(num_of_files, current_file_index) do
    Process.send_after(self(), {:start_search, num_of_files, current_file_index}, 1_000)
  end

  def handle_info(:fix_finger_table, current_map) do
    num_of_nodes = :ets.lookup_element(:global_values, :num_of_nodes, 2)

    # Update successors to include only alive nodes
    alive_successors =
      current_map.successor
      |> Enum.filter(fn x ->
        Process.whereis(x |> Integer.to_string() |> String.to_atom()) != nil
      end)

    {_, current_map} =
      Map.get_and_update(current_map, :successor, fn x -> {x, alive_successors} end)

    # last_successors_successors = GenServer.call(List.last(current_map.successor) |> Integer.to_string |> String.to_atom,
    #                              :get_successor_list) |> Enum.filter(fn x -> Process.whereis(x |> Integer.to_string |> String.to_atom) != nil end)
    # full_list = alive_successors ++ last_successors_successors

    # alive_node_list = 
    #   if length(full_list) > trunc(:math.log2(num_of_nodes)) * 2 do
    #     Enum.slice(full_list, 0, trunc(:math.log2(num_of_nodes)) * 2)
    #   else
    #     full_list
    #   end
    # 

    # Get finger table from successor
    universe =
      GenServer.call(
        Enum.at(current_map.successor, 0) |> Integer.to_string() |> String.to_atom(),
        :get_finger_table
      )

    # Form a universe of all known nodes for this node
    universe =
      (current_map.finger_table ++ current_map.successor ++ universe)
      |> Enum.filter(fn x ->
        Process.whereis(x |> Integer.to_string() |> String.to_atom()) != nil
      end)
      |> Enum.uniq()

    # Update finger table using the universe as the entire set of nodes in the system
    updated_finger_table =
      0..(length(current_map.finger_table) - 1)
      |> Enum.map(fn x ->
        value_to_find =
          rem(current_map.current_value + (1 <<< x), 1 <<< length(current_map.finger_table))

        Application1.find_immediate_successor(value_to_find, universe)
      end)

    {_, updated_map} =
      Map.get_and_update(current_map, :finger_table, fn x -> {x, updated_finger_table} end)

    # IO.inspect current_map
    # IO.puts "fixed fingertable for #{current_map.current_value}"

    periodic_fix_fingers()

    {:noreply, updated_map}
  end

  defp periodic_fix_fingers() do
    Process.send_after(self(), :fix_finger_table, 10_000)
  end

  def handle_call(:get_finger_table, _from, current_map) do
    {:reply, Enum.uniq(current_map.finger_table), current_map}
  end

  def handle_call(:get_predecessor, _from, current_map) do
    {:reply, current_map.predecessor, current_map}
  end

  def handle_call(:get_files, _from, current_map) do
    {:reply, current_map.local_file, current_map}
  end

  def handle_call(:get_successor_list, _from, current_map) do
    {:reply, current_map.successor, current_map}
  end

  def handle_info(:kill, current_map) do
    {:stop, :normal, current_map}
  end
end
