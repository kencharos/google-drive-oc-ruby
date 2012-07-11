
function readFile(file) {
     var reader = new FileReader();  
     reader.onload = function(e) {
		var el = document.createElement("object");
		el.setAttribute("type", file.type);
		el.setAttribute("data", e.target.result);
		el.setAttribute("width", "500px");
		$("#img").empty();
		$("#img").append(el);
		
     	$.post("file", {"name":file.name, "type":file.type, "content":e.target.result},
     		function(url) {
     			var a = document.createElement("a");
     			a.setAttribute("href", url)
     			a.setAttribute("target", "_blank")
     			a.innerHTML = "open new window"
     			var el = document.createElement("object");
				el.setAttribute("data", url);
				el.setAttribute("type", "text/html");
				el.setAttribute("width", "500px");
				$("#text").empty();
				$("#text").append("preview<br>")
				$("#text").append(el);
				$("#text").append("<br>")
				$("#text").append(a);
				
     		})
	}
	reader.readAsDataURL(file)
}
