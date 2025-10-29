(:
 : convert: RESTXQ-based API for transpect conversions
 : 
 :)
module namespace  conv                = 'http://transpect.io/convert';

declare variable $conv:config        := doc('config.xml')/conv:config;
declare variable $conv:auth          := doc('auth.xml')/conv:auth;
declare variable $conv:code-dir      := xs:string($conv:config/conv:code-dir);
declare variable $conv:data-dir      := xs:string($conv:config/conv:data-dir);
declare variable $conv:queue-path    := $conv:data-dir || '/' || 'queue';
declare variable $conv:queue-limit   := xs:integer($conv:config/conv:queue-limit);
declare variable $conv:polling-delay := xs:integer($conv:config/conv:polling-delay);

(:
 : List available converters
 : 
 : $ curl -G http://localhost:8080/converters
 :)
declare
  %rest:GET
  %rest:path("/converters")
function conv:converters() {
  '{ "converters":["' || string-join(for $dir in file:list($conv:code-dir) return replace($dir, '[\\/]', ''), '", "') || '"] }'
};
(:
 : Receive file and convert it 
 : with the selected converter.
 :
 : $ curl -i -X POST -H "Content-Type: multipart/form-data" -F converter=myconverter -F "file=@path/to/myfile.epub" http://localhost:8080/convert
 :)
declare
  %rest:POST
  %rest:path("/convert")
  %rest:form-param("token", "{$token}")
  %rest:form-param("file", "{$file}")
  %rest:form-param("converter", "{$converter}")
  %rest:form-param("params", "{$params}")  
function conv:convert($token as xs:string?, $file as map(*), $converter as xs:string, $params as xs:string?) {
  for $paths         in conv:paths($file, $converter, $params)
  let $valid         := conv:validate-token($token, $converter)
  let $input-dir     := $paths/input-dir
  let $output-dir    := $paths/output-dir
  let $path          := $paths/path
  let $status        := $paths/status
  let $process-id    := $paths/process-id 
  return 
    (conv:prepare($file, $paths),
     conv:execute($paths),
     conv:queue-remove($process-id),
     conv:set-status($paths, 'finished'))
};
(:
 : Create paths XML element.
 :)
declare function conv:paths($file as map(*), $converter as xs:string, $params as xs:string?) as element(paths) {
  for $name           in map:keys($file)
  let $content        := $file( $name )
  let $process-id     := random:uuid()
  let $converter-path := $conv:code-dir || '/' || $converter 
  let $status-path    := $conv:data-dir || '/' || $converter || '/' || $name || '/' || 'status'
  let $input-dir      := $conv:data-dir || '/' || $converter || '/' || $name || '/' || 'in'
  let $output-dir     := $conv:data-dir || '/' || $converter || '/' || $name || '/' || 'out'
  let $in-path        := $input-dir     || '/' || $name
  let $out-path       := $output-dir    || '/' || $name
  return 
    <paths>
      <code-dir>{ $conv:code-dir }</code-dir>
      <data-dir>{ $conv:data-dir }</data-dir>
      <input-dir>{ $input-dir }</input-dir>
      <output-dir>{ $output-dir }</output-dir>
      <queue-path>{ $conv:queue-path }</queue-path>
      <converter>{ $converter }</converter>
      <converter-path>{ $converter-path }</converter-path>
      <status-path>{ $status-path }</status-path>
      <process-id>{ $process-id }</process-id>
      <in-path>{ $in-path }</in-path>
      <out-path>{ $out-path }</out-path>
      <filename>{ $name }</filename>
      {  
        for $param in tokenize($params, ':')
        return <param name="{tokenize($param, '=')[1]}" value="{tokenize($param, '=')[2]}"/>
      } 
    </paths>
};
(:
 : Create paths etc.
 :)
declare function conv:prepare($file as map(*), $paths as element(paths)) {
  for $name           in map:keys($file)
  let $content        := $file( $name )
  return
    (file:create-dir($paths/input-dir),
     file:create-dir($paths/output-dir),
     file:write-binary($paths/in-path, $content),
     conv:set-status($paths, 'pending'),
     if (not(file:exists($paths/queue-path))) { file:write-text($paths/queue-path, '') },
     conv:queue-add($paths/process-id),
     file:copy($paths/in-path, $paths/out-path)
     )
};
(:
 : Writes the status file
 :)
declare function conv:set-status($paths as element(paths), $status as xs:string) {
  file:write-text($paths/status-path, $status)
};
(:
 : Add process id to queue file.
 :)
declare function conv:queue-add($process-id as xs:string) {
  let $wait := conv:wait-for-place-in-queue()
  return 
    file:append-text-lines($conv:queue-path, $process-id)
};
(:
 : Remove process id from queue file.
 :)
declare function conv:queue-remove($process-id as xs:string) { 
  let $queue-except-current := file:read-text-lines($conv:queue-path)[. != $process-id]
  return 
    file:write-text-lines($conv:queue-path, $queue-except-current) 
};
(: 
 : Wait until the number of lines in the queue 
 : file is lower than the queue limit.
 :)
declare function conv:wait-for-place-in-queue() {
  do-until(
    [(),
     (count(file:read-text-lines($conv:queue-path)) lt $conv:queue-limit)],
    function (){
      [prof:sleep($conv:polling-delay),
       count(file:read-text-lines($conv:queue-path)) lt $conv:queue-limit]
    },
    function($result){
      $result?2 eq true()                                   
    }
  )
};
(: 
 : Invokes the converter Makefile
 :)
declare function conv:execute($paths as element(paths)) {
  let $converter       := $paths/converter
  let $converter-path  := $paths/converter-path
  let $output-dir      := $paths/output-dir
  let $out-path        := $paths/out-path
  let $process-id      := $paths/process-id
  return (
      conv:set-status($paths, 'started'),
      proc:execute(
        'make', 
        ('-f', 
          $converter-path ||  '/' || 'Makefile',
          'conversion',
          'IN_FILE=' || $out-path,
          'OUT_DIR=' || $output-dir,
          for $param in $paths/param
          return $param/@name || '=' || $param/@value
         )
      )
   )
};
(: 
 : Prints the content of the queue file
 : 
 : $ curl http://localhost:8080/queue
 :)
declare
  %rest:GET
  %rest:path("/queue")
function conv:queue() {
    '{ "queue":["' || string-join(for $proc in file:read-text-lines($conv:queue-path) return $proc, '", "') || '"] }'
};
(: 
 : Gets the status of the current conversion.
 : 
 : $ curl http://localhost:8080/status/myconverter/myfile.epub
 :)
declare
  %rest:GET
  %rest:query-param("token", "{$token}")
  %rest:path("/status/{$converter=.+}/{$filename=.+}")
function conv:status($filename as xs:string, $converter as xs:string, $token as xs:string?) {
  let $valid       := conv:validate-token($token, $converter)
  let $status-path := $conv:data-dir || '/' || $converter || '/' || $filename || '/' || 'status'
  return '{ "status":"' || file:read-text($status-path) || '" }'
};
(: 
 : List the available downloads
 : 
 : $ curl http://localhost:8080/list/epub2epub/myfile.epub 
 :)
declare
  %rest:GET
  %rest:query-param("token", "{$token}")
  %rest:path("/list/{$converter=.+}/{$filename=.+}")
function conv:list($filename as xs:string, $converter as xs:string, $token as xs:string?) {
  let $valid       := conv:validate-token($token, $converter)
  let $output-dir  := $conv:data-dir || '/' || $converter || '/' || $filename || '/' || 'out'
  return 
    if( json:parse( conv:status($filename, $converter, $token))/json/status = 'finished' )
    then concat(
           '{ "results":[',
           string-join(
             (for $file in file:list($output-dir)
              return 
                if(file:is-file($output-dir || '/' || $file)) 
                  { '"' || '/download/' || $converter || '/' || $filename || '/' || $file || '"' } 
             ),
             ','
           ),
           '] }'
         )
    else 'No results found. Conversion status:' || conv:status($filename, $converter, $token)
};
(:
 : Download files from the output dir.
 : 
 : $ curl --output myfile.epub -G http://localhost:8080/download/myconverter/myfile.epub/myresult.txt
 :)
declare
  %rest:GET
  %rest:query-param("token", "{$token}")
  %rest:path("/download/{$converter=.+}/{$filename=.+}/{$result=.+}")
  %perm:allow("all")
function conv:download( $result as xs:string, $filename as xs:string, $converter as xs:string, $token as xs:string? ) as item()+ {
  let $valid       := conv:validate-token($token, $converter)
  let $output-dir := $conv:data-dir || '/' || $converter || '/' || $filename || '/' || 'out'
  let $path := $output-dir || '/' || $result
  return
    (
     web:response-header(
       map {'media-type': web:content-type( $path )},
       map {'Cache-Control': 'max-age=3600,public', 'Content-Length': file:size( $path )}
     ),
       file:read-binary( $path )
     )
};
declare function conv:validate-token( $token as xs:string?, $converter as xs:string ) {
  let $key := $conv:auth/conv:converter[conv:name = $converter]/conv:key
  return
    if(    exists($conv:auth/conv:converter[conv:name = $converter]) 
       and not($conv:auth/conv:converter[conv:name = $converter]/conv:token = crypto:hmac($token, $key, 'sha256', 'hex')))
      { error(xs:QName('err:auth001'), $converter) }
};
declare
  %rest:error("err:auth001")
  %rest:error-param("code", "{$code}")
  %rest:error-param("description", "{$converter}")
function conv:token-error($code as xs:string, $converter as xs:string) {
  let $response :=  '[HTTP/1.1 401 Unauthorized] ' || $code || ': The submitted token is not valid for converter "' || $converter|| '".'
  return web:error(401, $response)
};
(:
 : Describes the API in form of a WADL document
 :)
declare
  %rest:GET
  %rest:path("/apidoc")
function conv:apidoc() {
  rest:wadl()
};
