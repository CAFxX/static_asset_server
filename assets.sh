#!/usr/bin/env bash
(
    cd assets/source
    echo "<table><thead><tr><th>Source<th>Optimized variants<tbody>"
    for FILE in *; do 
        SS=$(wc -c <"$FILE" | xargs)
        echo "<tr><td><a href=\"assets/source/$FILE\">$FILE</a> ($SS bytes)<td>"
        (
            cd ../optimized
            for OFILE in ${FILE}*; do
                OS=$(wc -c <"$OFILE" | xargs)
                echo "<a href=\"assets/optimized/$OFILE\">$OFILE</a> ($OS bytes)<br>"
            done
        )
    done
    echo "</table>"
)
