param($data)

return html {
    head {
        title 'Pode Page'
        link -href 'styles/simple.css' -rel 'stylesheet' -type 'text/css'
        script 'scripts/simple.js'
    }

    body {
        p {
            'Hello, world! This is Pode page!'
        }

        foreach ($i in $data.numbers) {
            "<li>value: $i</li>"
        }

        img 'Anger.jpg'
    }
}