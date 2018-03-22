================================
 Network Coding Network Toolbox
================================

Description
===========

Provides several network coding tools for use in real networks:

 * `ncif` - Creates a virtual interface that encodes received packets and sends them back.
 * `ncigmp` - Registers to an IGMP multicast, encode the packets and send them out again.
 * `ncctl` - Modify runtime parameters in the other tools.

Dependencies
============

 * nckernel

Compiling
=========

It is recommended to compile the project in a separate directory. This can be done
with the following steps::

    mkdir build
    cd build
    cmake ..

This will setup the build system. After the initial configuration you can
compile the project with `make`::

    make

After compiling you have the three programs in the `bin` directory.

Usage
=====

The command `ncif` creates a virtual network interface with network coding. The
interface cannot be used like other network interfaces, because it does not
really send the packets anywhere. Instead it is intended to be used with
openvswitch. With openvswitch the packet can be forwarded to the virtual
interface, and when it comes back can be routed to the next hop.

In the following example we will construct a simple emulated network topology with
openvswitch::

    h1 ---- s1 ----- s2 ---- h2
            |        |
           nc1      nc2

The nodes `h1` and `h2` are emulated hosts. They get a network namespace and an
IP address and will communicate with each other. The nodes `s1` and `s2` are
openvswitch bridges. They will forward the traffic between `h1` to `h2`. The
nodes `nc1` and `nc2` are created using the `ncif` command. `nc1` will be the
encoder and `nc2` the decoder in our example.

First we setup the host nodes::

    sudo ip netns add h1
    sudo ip netns add h2

Next we create the openvswitch bridges::

    sudo ovs-vsctl add-br s1
    sudo ovs-vsctl add-br s2

Then we create the virtual links between our nodes::

    sudo ip link add h1-s1 type veth peer name s1-h1
    sudo ip link add s1-s2 type veth peer name s2-s1
    sudo ip link add s2-h2 type veth peer name h2-s2

Now we connect our links to the hosts::

    sudo ip link set h1-s1 netns h1
    sudo ip link set h2-s2 netns h2

And the other end of the links to our openvswitches::

    sudo ovs-vsctl add-port s1 s1-h1 -- set interface s1-h1 ofport_request=1
    sudo ovs-vsctl add-port s1 s1-s2 -- set interface s1-h1 ofport_request=2
    sudo ovs-vsctl add-port s2 s2-s1 -- set interface s1-h1 ofport_request=1
    sudo ovs-vsctl add-port s2 s2-h2 -- set interface s1-h1 ofport_request=2

We need to configure the IP addresses of the hosts::

    sudo ip netns exec h1 ip addr add dev h1-s1 10.0.0.1/24
    sudo ip netns exec h2 ip addr add dev h2-s2 10.0.0.2/24

Finally we start the interfaces::

    sudo ip netns exec h1 ip link set h1-s1 up
    sudo ip link set s1-h1 up
    sudo ip link set s1-s2 up
    sudo ip link set s2-s1 up
    sudo ip link set s2-h2 up
    sudo ip netns exec h2 ip link set h2-s2 up

After this we should have our virtual network up and running. We can test this
with a simple ping::

    sudo ip netns exec h1 ping 10.0.0.2

If this is working our demo network is almost complete. We are now only missing
the network coding interfaces. Start this in separate terminals, because the
program will remain running for the whole experiment::

    sudo ncif --name nc1 --control /var/run/nc1.sock --encode sliding_window
    sudo ncif --name nc2 --control /var/run/nc2.sock --decode sliding_window

The interfaces need to be connected to the switches according to our topology::

    sudo ovs-vsctl add-port s1 nc1 -- set interface nc1 ofport_request=3
    sudo ovs-vsctl add-port s2 nc2 -- set interface nc2 ofport_request=3

We want to send all traffic from `h1` first to `nc1` to encode it::

    sudo ovs-ofctl add-flow s1 "priority=1000,in_port=1,ip action=3"

We also want to forward the coded traffic towards `s2`::

    sudo ovs-ofctl add-flow s1 "priority=1000,in_port=3 action=2"

Additionally we prevent all other packets to be flooded towards the coding interface::

    sudo ovs-ofctl mod-port s1 nc1 no-flood

We repeat the same for `s2`. The traffic comming from `s2` will be sent to the decoder.
The decoded packets are forwarded to `h2`. And we disable flooding on `nc2`::

    sudo ovs-ofctl add-flow s2 "priority=1000,in_port=1,ip action=3"
    sudo ovs-ofctl add-flow s2 "priority=1000,in_port=3 action=2"
    sudo ovs-ofctl mod-port s2 nc2 no-flood

Now the topology is completely setup. We can review the openvswitch configuration::

    sudo ovs-ofctl dump-ports-desc s1
    sudo ovs-ofctl dump-ports-desc s2
    sudo ovs-ofctl dump-flows s1
    sudo ovs-ofctl dump-flows s2

We now enable the network coding interfaces::

    sudo ip link set nc1 up
    sudo ip link set nc2 up

Now all UDP packets going from `h1` to `h2` will be send through `nc1` and
`nc2` where they are encoded resp. decoded. To show this we run a small example.

First we use two separate terminals to run `tcpdump` on our interfaces::

    sudo tcpdump -i nc1
    sudo tcpdump -i nc2

Then we start a simple UDP server on `h2` in another terminal::

    sudo ip netns exec h2 nc -u -l -p 9000

On the node `h1` we run the UDP client::

    sudo ip netns exec h1 nc 10.0.0.2 9000

When we now type in the terminal on `h1` we will see the message appear on `h2`.
Also we will see the messages in `tcpdump`. On `nc1` we see the message we typed as
incomming packet and we see a slightly larger packet as output. On the other side
we see in `nc2` the incomming packet as it was sent by `nc1`. The outgoing packet
from `nc2` will again be the clear text message we typed into `h1`.

This shows that the message was encoded in `nc1` and decoded in `nc2`. This setup
can now be distributed on multiple real machines. But you have to find out how to
send the packets into encoding and decoding interfaces.
