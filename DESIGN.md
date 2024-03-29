* From CAP theorem prospective we need to have Consistency + Partition tolerance. We should dismiss Availability for particular nodes/partitions/clusters: when a node/aprtition/cluster does not responce, then we assume it is down. When it does not responce we should not make any assumtion about the node and jobs on it: they are lost completely.
* We should keep a list of alive hosts separatly from vnodes list. When host becomes alive we check what vnodes should be started there and start them.
* We need to be able to start several vnodes on the same host. The name of node is <vnodename>@<hostname>, for example compute@node003.
* On boot vnodes are loaded by parent. The parent uses hostname to get how many (and what kind of) vnodes should be started on the host.
* Any of those fallacies should be taken into account: https://blogs.oracle.com/jag/resource/Fallacies.html
* Concistency ensuring strategy:
  1. When parent dies, one of its child starts the parent on its host. Which child takes this responsibility is chosen by leader election algorithm among all children. This child is called assisting child. New parent is called a secondary parent.
  2. Each vnode uses its own prioritized queue of parents. When primary parent comes back, then it notifies all its children that it is alive and the children switch to this old parent.
  3. When primary parent comes back, then all started secondary parents will stop.
  4. Each alteration (a new record) is spread "vertically" along a nodes tree up and down with md5 sum of final record. The record is red after write and its md5 sum is compared with received sum.
  5. Each child sends confirmation about applied alteration only when all its children confirm their alterations (branch transaction). If vnode is not in one of the working states, then the vnode is not taking into account (when it comes back, it will clone all configuration of its parent).
  6. There is only one logical path to spread the alteration over the nodes tree. If topology is changed during the alteration, then the alteration is considered unsuccessful (because children don't confirm alteration by timeout) and should be repeated by the node which initiated the alteration. 
  7. There could be several physical paths to deliver the alteration to a vnode. A directional reachability graph can help to deliver the alteration faster.
  8. Each system data modification is unified by generic alteration propagation mechanism incapsulated in wm_alter module: config is altered by admin, topology is modified by failover, job or vnode state is changed. Reachability graph should not be known outside this module.
