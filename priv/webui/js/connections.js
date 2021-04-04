
var width = 800;
var height = 500;
var color = d3.scale.category20();
var iter = 0;
var nodes = {};
var json_nodes = {};
var update_interval = 1; // seconds
var limit = 100;

var current = 0;
var since = 0;
var to = 0;
var step = 1; // seconds

function prepare_layout() {
  var force = d3.layout.force()
                .charge(-300)
                .linkDistance(80)
                .gravity(.05)
                .size([width, height]);
  return force;
}

function prepare_svg() {
  var svg =  d3.select("body").append("svg")
               .attr("width", width)
               .attr("height", height);

  // build the arrow
  svg.append("svg:defs").selectAll("marker")
      .data(["msg_route"])
    .enter()
      .append("svg:marker")
        .attr("id", function(d) { return d; })
        .attr("viewBox", "0 -5 10 10")
        .attr("refX", 15)
        .attr("refY", 0)
        .attr("markerWidth", 4)
        .attr("markerHeight", 4)
        .attr("orient", "auto")
      .append("svg:path")
        .attr('d', function(d){ return d.path })

  return svg;
}

function draw_nodes(force, svg) {
  d3.json("http://localhost:8008/grid",
    function(error, json) {
      if(error) throw error;
      json_nodes = json.nodes;

      console.log(json_nodes);
      links = [];
      json_nodes.forEach(function(nd) {
        nodes[nd.name] = {name: nd.name};
        nodes[nd.name].subname = nd.subname;
        nodes[nd.name].subid = nd.subid;
        if(nd.subname == "cluster") {
          nodes[nd.name].y=60;
        };
        if(nd.subname == "grid") {
          nodes[nd.name].fixed = true;
          nodes[nd.name].x=400;
          nodes[nd.name].y=10;
        };
      });
      json_nodes.forEach(function(nd) {
        var link = {};
        link.source = nodes[nd.name];
        link.target = nodes[nd.parent];
        links.push(link);
      });
      console.log(links);

      force
        .nodes(d3.values(nodes))
        .links(links)
        .on("tick", function() { tick_nodes(svg) });

      var path = svg.append("svg:g").selectAll("path").data(force.links());

      path.enter()
          .append("svg:path")
          .attr("class", "relation");

      // define the nodes
      var node = svg.selectAll(".node")
                    .data(force.nodes());
      node.enter()
          .append("svg:g")
          .attr("class", "node");

      // add the nodes
      node.append("circle")
        .attr("r", 5)
        .style("fill", function(d) { return color(d.subname+d.subid) })
        .call(force.drag);

      // add the text
      node.append("text")
        .attr("x", 8)
        .attr("dy", ".35em")
        .text(function(d) { return d.name; });

      node.exit().remove();

      force.start();
    }
  );
}

function next_t1() {
  var t1 = current;
  current = current + step*1000000;
  return t1;
}
function next_t2() {
  var t2 = current;
  return t2;
}

// http://bl.ocks.org/d3noob/5141278
function draw_links(force, svg) {
  var metric = document.getElementById('metricname').value;
  var t1 = next_t1();
  var t2 = next_t2();

  console.log("Step: " + iter++ + " | t1=" + t1 + " t2=" + t2);

  for(var i = 0; i < json_nodes.length; ++i) {
    nodes[json_nodes[i].name].fixed = true;
  }

  svg.selectAll('.link').remove();

  var params = "metric=" + metric + "&begintime=" + t1 + "&endtime=" + t2 + "&limit=" + limit;
  d3.json("http://localhost:8008/mon?" + params, function(error, json) {
    if(error) throw error;
    if(json.metrics.length==0) return;

    json.metrics.forEach(function(link) {
      link.source = nodes[link.s] || (nodes[link.s] = {name: link.s});
      link.target = nodes[link.d] || (nodes[link.d] = {name: link.d});
    });
    console.log(json.metrics);

    force
      .nodes(force.nodes())
      .links(json.metrics)
      .on("tick", function() { tick_nodes(svg) });


    var path = svg.append("svg:g").selectAll("path").data(force.links());

    path.enter()
        .append("svg:path")
          .attr('d', function(d,i){ return 'M 0,' + (i * 100) + ' L ' + width + ',' + (i * 100) + '' })
          //.attr("class", function(d) { return "link " + d.type; })
          .attr("class", "link")
          //.attr("marker-end", function(d) { return "url(#" + d.type + ")"; });
          .attr("marker-end", function(d) { return "url(#msg_route)"; })

    path
        .transition()
        .duration(update_interval*1000)
        .style("opacity", 0.0)
        .remove();

    force
      .alpha(0.008)

  });
}

function tick_nodes(svg) {
  var path = svg.selectAll("path");
  path.attr("d", function(d) {
      if (typeof(d.target) == 'undefined') {
        return "M0,-5L10,0L0,5";
      }
      return "M" +
          d.source.x + "," +
          d.source.y +
          "A0,0 0 0,1 " +
          d.target.x + "," +
          d.target.y;
  });

  var node = svg.selectAll(".node");
  node.attr("transform",
            function(d) {
              return "translate(" + d.x + "," + d.y + ")";
            }
           );
}

function tick_links(svg) {
  var path = svg.selectAll("path");
  path.attr("d", function(d) {
      if (typeof(d.target) == 'undefined') {
        return "M0,-5L10,0L0,5";
      }
      var dx = d.target.x - d.source.x,
          dy = d.target.y - d.source.y,
          //dr = Math.sqrt(dx * dx + dy * dy);
          dr = 0;
      return "M" +
          d.source.x + "," +
          d.source.y + "A" +
          dr + "," + dr + " 0 0,1 " +
          d.target.x + "," +
          d.target.y;
  });
}

console.log("Start");
var force = prepare_layout();
var svg = prepare_svg();
var refreshIntervalId = 0;

d3.select('#play').on('click', function() {
  since = Date.parse(document.getElementById('since').value)*1000;
  to = Date.parse(document.getElementById('to').value)*1000;
  current = since;
  refreshIntervalId = setInterval(function() {
      draw_links(force, svg);
    },
    update_interval*1000
  );
});

d3.select('#stop').on('click', function() {
  if (force && refreshIntervalId) {
    force.stop();
    clearInterval(refreshIntervalId);
  }
});

function set_defaults() {
  var ms_in_minute = 60000;
  var from_date = new Date(Date.now() - ms_in_minute);
  var now = new Date(Date.now());
  document.getElementById('since').value = from_date.toISOString();
  document.getElementById('to').value = now.toISOString();
}

set_defaults();
draw_nodes(force, svg);
draw_links(force, svg);

