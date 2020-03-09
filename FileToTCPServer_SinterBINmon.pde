import processing.net.*;
import java.lang.RuntimeException;
import java.util.Arrays;
import java.io.FilenameFilter;

ArrayList<FileToTCPServer> FileToTCPServer_list;

int get_int_diff(int new_val, int old_val)
{
  int diff;

  if (new_val < old_val) diff = MAX_INT - old_val + new_val - MIN_INT;
  else diff = new_val - old_val;

  return diff;
}

class FileToTCPServer {
  String server_ip;
  int server_port;
  int interval_sec;
  String data_directory;
  String data_file_prefix;
  Server tcp_server_handle;
  String[] data_file_list;
  int data_file_list_count;
  int data_file_list_index;
  byte[] data_load_buf;
  int data_write_index;
  int data_write_bytes_per_sec;
  int data_write_start_millis; 
  int data_write_last_millis; 

  FileToTCPServer(PApplet parent, String server_ip, int server_port, int interval_sec, String data_directory, String data_file_prefix) {
    this.server_ip = server_ip;
    this.server_port = server_port;
    if (interval_sec < 1) {
      this.interval_sec = 1;
    }
    else if (interval_sec > 10) {
      this.interval_sec = 10;
    }
    else {
      this.interval_sec = interval_sec;
    }
    this.data_directory = data_directory;
    if (data_file_prefix == null || data_file_prefix == "") {
      this.data_file_prefix = "All";
    }
    else {
      this.data_file_prefix = data_file_prefix;
    }

    if (server_ip.charAt(0) == '#') {
      tcp_server_handle = null;
    }
    else if (server_ip == null || server_ip == "" || server_ip.equals("0.0.0.0")) {
      try {
        tcp_server_handle = new Server(parent, server_port);  // Start a simple server on a port
      }
      catch (RuntimeException e) {
        tcp_server_handle = null;
      }
    }
    else {
      try {
        tcp_server_handle = new Server(parent, server_port, server_ip);  // Start a simple server on a port
      }
      catch (RuntimeException e) {
        tcp_server_handle = null;
      }
    }

    if (tcp_server_handle == null) {
      return;
    }

    File data_directory_handle;

    data_directory_handle = new File(data_directory);

    if (!data_directory_handle.isAbsolute()) {
      data_directory_handle = new File(sketchPath() + "\\" + data_directory);
    }

    if (!data_directory_handle.isDirectory()) {
      return;
    }

    if (data_file_prefix == null || data_file_prefix == "") {
      data_file_list = data_directory_handle.list();
    }
    else {
      final String filename_prefix = data_file_prefix;
      data_file_list =
        data_directory_handle.list(
          new FilenameFilter() {
            @ Override final boolean accept(File dir, String name) {
              //println("name=" + name);
              return
                name.length() > filename_prefix.length()
                &&
                name.substring(0, filename_prefix.length()).equals(filename_prefix)
                &&
                name.toLowerCase().endsWith(".txt");
            }
          }
        );
    }

    if (data_file_list != null && data_file_list.length > 0) {
      Arrays.sort(data_file_list);
    }

    data_write_start_millis = millis();

    data_file_list_count = data_file_list.length;
    data_file_list_index = 0;

    println("data_file_list_count=" + data_file_list_count);
    //for (String file_name:data_file_list) {
    //  println("file_name=" + file_name);
    //}
  }

  void close() {
    if (tcp_server_handle == null) return;

    tcp_server_handle.stop();
    tcp_server_handle = null;
  }

  void reset() {
    if (tcp_server_handle == null) return;

    data_file_list_index = 0;
    data_load_buf = null;
  }

  void write_file_2_tcp_init(int bytes_per_sec) {
    if (tcp_server_handle == null) return;
    if (data_file_list_count == 0) return;

    data_load_buf = loadBytes(data_directory+"\\"+data_file_list[data_file_list_index]);

    data_write_index = 0;
    data_write_bytes_per_sec = bytes_per_sec;
    data_write_start_millis = data_write_last_millis = millis();

    data_file_list_index ++;
    if (data_file_list_index >= data_file_list_count)
      data_file_list_index = 0;
  }

  void write_file_2_tcp_continue() {
    if (tcp_server_handle == null) return;
    if (data_file_list_count == 0) return;

    if (data_load_buf == null) return;
    if (data_write_index >= data_load_buf.length) return;

    int data_write_bytes;
    int data_write_curr_millis = millis();
    int diff = get_int_diff(data_write_curr_millis, data_write_last_millis);

    data_write_last_millis = data_write_curr_millis;

    if (diff <= 0) return;

    data_write_bytes = data_write_bytes_per_sec * diff / 1000;
    //println("data_write_bytes=" + data_write_bytes);
    if (data_write_bytes == 0) return;

    byte[] data_write_buf;

    data_write_buf = Arrays.copyOfRange(data_load_buf, data_write_index, ((data_load_buf.length - data_write_index) > data_write_bytes)?(data_write_index + data_write_bytes):data_load_buf.length);
    tcp_server_handle.write(data_write_buf);

    data_write_index += data_write_bytes;
    if (data_write_index >= data_load_buf.length) {
      data_write_index = data_load_buf.length;
    }
  }

  void write(byte[] data_buf) {
    if (tcp_server_handle == null) return;
    tcp_server_handle.write(data_buf);
  }

}

final static int FRAME_RATE = 10;
final static int BITS_PER_SECOND = 115200;
final static int BITS_TO_BYTES = 12;

void setup() {
  size(640, 300);
  background(250);
  fill(0);
  stroke(0);
  textAlign(LEFT, TOP);

  frameRate(FRAME_RATE); // Slow it down a little

  FileToTCPServer_list = new ArrayList<FileToTCPServer>();

  Table table;

  // Load lines file(CSV type) into a Table object
  // "header" option indicates the file has a header row
  table = loadTable(sketchPath() + "\\data\\" + "config.csv", "header");
  // Check loadTable ok.
  if(table != null) {
    for (TableRow variable:table.rows()) {
      String server_ip = variable.getString("Server_IP");
      int server_port = variable.getInt("Server_Port");
      int interval_sec = variable.getInt("Interval_Sec");
      String data_directory = variable.getString("Data_Directory");
      String data_file_prefix = variable.getString("Data_File_Prefix");

      println("Server_IP=" + server_ip);
      println("Server_Port=" + server_port);
      println("Interval_Sec=" + interval_sec);
      println("Data_Directory=" + data_directory);
      println("Data_File_Prefix=" + data_file_prefix);

      FileToTCPServer tcp_server =
        new FileToTCPServer(
          this,
          server_ip,
          server_port,
          interval_sec,
          data_directory,
          data_file_prefix);

      FileToTCPServer_list.add(tcp_server);
    }
  }

  //s = new Server(this, 7001, "192.168.0.71");  // Start a simple server on a port
}

void draw() {
  background(250);

  ArrayList<String> strings = new ArrayList<String>();

  for(FileToTCPServer ftts:FileToTCPServer_list) {
    String string;
    string = ftts.server_ip + ":" + ftts.server_port + ":" + ftts.interval_sec + " " + ftts.data_directory + " " + ftts.data_file_prefix + " ";
    if (ftts.tcp_server_handle != null) {
      string += "O " + ftts.data_file_list_count + " ";
      if (ftts.data_file_list_count == 0) {
        string += "No files ";
      }
      if (ftts.tcp_server_handle.clientCount > 0) {
        string += ftts.tcp_server_handle.clientCount + " ";
        if (ftts.data_file_list_count != 0) {
          string += ftts.data_file_list_index + " " + ftts.data_file_list[ftts.data_file_list_index];
        }
      }
      else
      {
        string += "No clients";
      }
    }
    else {
      string += "X";
    }
    strings.add(string);

    if (ftts.tcp_server_handle != null) {
      if (ftts.tcp_server_handle.clientCount > 0) {
        if (ftts.data_file_list_count != 0) {
          // Receive data from client
          Client client;
          client = ftts.tcp_server_handle.available();
          if (client != null) {
            byte[] input;

            input = client.readBytes();
            //input = input.substring(0, input.indexOf("\n"));  // Only up to the newline
          }

          if (get_int_diff(millis(), ftts.data_write_start_millis) >= ftts.interval_sec * 1000 ) {
            ftts.write_file_2_tcp_init(BITS_PER_SECOND/BITS_TO_BYTES);
          }
          ftts.write_file_2_tcp_continue();
        }
      }
      else
      {
        ftts.data_file_list_index = 0;
      }
    }
  }

  int i = 0;
  for (String string:strings)
  {
    text(string, 5, i * 15);
    i ++;
  }

}

import java.awt.event.KeyEvent;

void keyPressed()
{
  if (key == ESC)
  {
    key = 0;  // Prevents the ESC key from being used.
  }
  else if(key == CODED)
  {
    if(keyCode == KeyEvent.VK_F4)
    {
      for(FileToTCPServer ftts:FileToTCPServer_list)
      {
        ftts.reset();
      }
    }
    else if(keyCode == KeyEvent.VK_F5)
    {
      for(FileToTCPServer ftts:FileToTCPServer_list)
      {
        ftts.close();
      }
      // To restart program set frameCount to -1, this wiil call setup() of main.
      frameCount = -1;
    }
  }
}
