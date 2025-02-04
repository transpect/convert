(:
 : convert: RESTXQ-based API for transpect conversions
 : 
 :)
module namespace  conv                = 'http://transpect.io/convert';
declare namespace c                   = 'http://www.w3.org/ns/xproc-step';

declare variable $conv:config        := doc('config.xml')/conv:config;
declare variable $conv:code-dir      := xs:string($conv:config/conv:code-dir);
declare variable $conv:data-dir      := xs:string($conv:config/conv:data-dir);
declare variable $conv:queue-path    := $conv:data-dir || file:dir-separator() || 'queue';
declare variable $conv:queue-limit   := xs:integer($conv:config/conv:queue-limit);
declare variable $conv:polling-delay := xs:integer($conv:config/conv:polling-delay);

(:
 : Receive file and convert it 
 : with the selected converter.
 :
 : $ curl -i -X POST -H "Content-Type: multipart/form-data" -F converter=epub2epub -F "file=@path/to/myfile.epub" http://localhost:8080/convert
 :)
declare
  %rest:POST
  %rest:path("/convert")
  %rest:form-param("file", "{$file}")
  %rest:form-param("converter", "{$converter}", "")
function conv:convert($file as map(*), $converter as xs:string) {
  for $paths         in conv:paths($file, $converter)
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
declare function conv:paths($file as map(*), $converter as xs:string) as element(paths) {
  for $name           in map:keys($file)
  let $content        := $file( $name )
  let $process-id     := random:uuid()
  let $converter-path := $conv:code-dir || file:dir-separator() || $converter 
  let $status-path    := $conv:data-dir || file:dir-separator() || $converter || file:dir-separator() || $name || file:dir-separator() || 'status'
  let $input-dir      := $conv:data-dir || file:dir-separator() || $converter || file:dir-separator() || $name || file:dir-separator() || 'in'
  let $output-dir     := $conv:data-dir || file:dir-separator() || $converter || file:dir-separator() || $name || file:dir-separator() || 'out'
  let $in-path        := $input-dir     || file:dir-separator() || $name
  let $out-path       := $output-dir    || file:dir-separator() || $name
  return 
    <paths>
      <code-dir>{ xs:string($conv:code-dir) }</code-dir>
      <data-dir>{ xs:string($conv:data-dir) }</data-dir>
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
     conv:set-status($paths, 'started'),
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
 : Invokes the converter Makefile, to-do: custom parameters
 :)
declare function conv:execute($paths as element(paths)) {
  let $converter       := $paths/converter
  let $converter-path  := $paths/converter-path
  let $output-dir      := $paths/output-dir
  let $out-path        := $paths/out-path
  let $process-id      := $paths/process-id
  return
    proc:execute(
      'make', 
      ('-f', 
        $converter-path || '/Makefile',
        'conversion',
        'IN_FILE=' || $out-path,
        'OUT_DIR=' || $output-dir
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
  file:read-text($conv:queue-path)   
};
(: 
 : Gets the status of the current conversion.
 : 
 : $ curl http://localhost:8080/status/epub2epub/myfile.epub
 :)
declare
  %rest:GET
  %rest:path("/status/{$converter=.+}/{$filename=.+}")
function conv:status($filename as xs:string, $converter as xs:string) {
  let $status-path := $conv:data-dir || file:dir-separator() || $converter || file:dir-separator() || $filename || file:dir-separator() || 'status'
  return file:read-text($status-path)
};
(: 
 : List the available downloads
 : 
 : $ curl http://localhost:8080/list/myfile.epub 
 :)
declare
  %rest:GET
  %rest:path("/list/{$converter=.+}/{$filename=.+}")
function conv:list($filename as xs:string, $converter as xs:string) {
  let $output-dir  := $conv:data-dir || file:dir-separator() || $converter || file:dir-separator() || $filename || file:dir-separator() || 'out'
  return 
    if(conv:status($filename, $converter) = 'finished')
    then concat(
           '{"results":[',
           string-join(
             (for $file in file:list($output-dir)
              return 
                if(file:is-file($output-dir || file:dir-separator() || $file)) 
                  { '"' || '/downloads/' || $converter || '/' || $file || '"' } 
             ),
             ','
           ),
           ']}'
         )
    else 'No results found. Conversion status:' || conv:status($filename, $converter)
};
(:
 : Download files from the output dir.
 : http://localhost:8080/results/epub2epub/myfile.epub
 : 
 : $ curl --output myfile.epub -G http://localhost:8080/download/epub2epub/myfile.epub 
 :)
declare
%rest:path("/download/{$converter=.+}/{$filename=.+}")
%perm:allow("all")
function conv:download( $filename as xs:string, $converter as xs:string ) as item()+ {
  let $output-dir := $conv:data-dir || file:dir-separator() || $converter || file:dir-separator() || $filename || file:dir-separator() || 'out'
  let $path := $output-dir || file:dir-separator() || $filename
  return
    (
     web:response-header(
       map {'media-type': web:content-type( $path )},
       map {'Cache-Control': 'max-age=3600,public', 'Content-Length': file:size( $path )}
     ),
       file:read-binary( $path )
     )
};
(:
 : Describes the API in form of a WADL document
 :)
declare
%rest:path("/apidoc")
function conv:apidoc() {
  rest:wadl()
};