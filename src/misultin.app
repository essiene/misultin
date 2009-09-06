{application, misultin,
 [{description, "HTTP Server library"},
  {vsn, '0.2.1'},
  {modules, 
      [
          misultin_socket,
          misultin_req,
          misultin
      ]
  },
  {registered, [misultin]},
  {env, []},
  {applications, [kernel, stdlib]}
 ]
}.
