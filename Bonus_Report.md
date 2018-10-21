### Bonus Report

* To demonstrate fault-tolerence we performed the file lookup operation twice: one in case of no failure and the other in case of failure.

* We observed that even in the presence of a node failure, the network is able to lookup the file correctly in the distributed hash table.

* This is because each file is being replicated at its predecessor node and _r_ successor nodes, where _r_ is 2log(n). 

* An interesting point of observation is that this specific value of _r_ ensures that the files are found even when 50% of the nodes have failed.

* Another interesting point of observation is that the average number of hops is always O(Lg(numNodes)).
