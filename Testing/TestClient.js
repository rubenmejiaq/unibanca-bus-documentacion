// Importing dgram module
var dgram = require('dgram');
 
// Creating and initializing client
// and server socket
var client = dgram.createSocket("udp4");

 
// Client sending message to server
// by using send() method
client.send("Hello", 0, 7, 1234, "localhost");