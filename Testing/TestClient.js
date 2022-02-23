// Importing dgram module
var dgram = require('dgram');
 
// Creating and initializing client
// and server socket
var client = dgram.createSocket("udp4");

 
// Client sending message to server
// by using send() method
client.send("1234XXXXXXXXXXXXXXX", 0, 7, 8005, "192.168.1.16");