$document_count = 9600

$mongoUrl = "mongodb://localhost/demo"

mgeneratejs -n $document_count .\datagen.json | mongoimport --db demo --collection prospect $mongoUrl