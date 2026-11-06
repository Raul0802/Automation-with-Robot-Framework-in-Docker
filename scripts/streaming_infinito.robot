*** Settings ***
Library      SeleniumLibrary    run_on_failure=Nothing
Library      DateTime
Library      OperatingSystem

*** Variables ***
${URL_STREAMING}    https://SEU_IP_AQUI:8081/
${TEMPO_VIDEO}      250
# LATÊNCIA PERSISTENTE: Salva na pasta de relatórios mapeada.
${LATENCY_FILE}     ${OUTPUT DIR}/latency.txt

${MOONLIGHT_USER}   SEU_USUARIO
${MOONLIGHT_PASS}   SUA_SENHA
${HOST_ID}          SEU_HOST_ID

*** Test Cases ***
Streaming Loop Simulation
    # LOOP INFINITO com recuperação automática de falhas
    WHILE    True
        ${status}    ${erro}=    Run Keyword And Ignore Error    Assistir Video Completo
        Run Keyword And Ignore Error    Close All Browsers
        IF    $status == 'FAIL'
            Log To Console    [WARN] Iteração falhou: ${erro}. A reiniciar em 10s...
            Sleep    10s
        ELSE
            Log To Console    [INFO] Iteração concluída. Aguardando 5s...
            Sleep    5s
        END
    END
    [Teardown]    Close All Browsers

*** Keywords ***
Assistir Video Completo
    Run    rm -rf /tmp/chrome_stream_*

    Abrir Navegador Streaming

    Go To    ${URL_STREAMING}
    Set Window Size    1920    1080

    Wait Until Element Is Visible    id=ml-api-name    timeout=30s
    Input Text                       id=ml-api-name    ${MOONLIGHT_USER}
    Input Password                   id=ml-api-password  ${MOONLIGHT_PASS}
    Click Element                    xpath=//button[text()='Ok']

    Wait Until Page Contains Element    xpath=//div[@id='modal-overlay' and contains(@class, 'modal-disabled')]    timeout=10s
    Execute Javascript    document.getElementById('modal-overlay').style.display='none';

    # Aguarda que a lista de hosts carregue (qualquer host-element visível)
    ${any_host}=    Run Keyword And Return Status
    ...    Wait Until Element Is Visible    xpath=//li[contains(@class, 'host-element')]    timeout=60s
    IF    not ${any_host}
        Capture Page Screenshot    ${OUTPUT DIR}/debug_sem_hosts.png
        Fail    Nenhum host apareceu na lista após 60s. Servidor Moonlight inacessível?
    END

    # Procura o host específico pelo seu ID (alterado para usar variável)
    ${TILE_HOST}    Set Variable    xpath=//li[contains(@class, 'host-element') and contains(., '${HOST_ID}')]
    ${host_ok}=    Run Keyword And Return Status    Element Should Be Visible    ${TILE_HOST}
    IF    not ${host_ok}
        Capture Page Screenshot    ${OUTPUT DIR}/debug_host_nao_encontrado.png
        Fail    Host '${HOST_ID}' não está na lista. Hosts presentes mas não o esperado.
    END
    Sleep    1s
    Click Element    ${TILE_HOST}

    ${TILE_XONOTIC}    Set Variable    xpath=(//li[contains(@class, 'app-element')])[3]
    Wait Until Element Is Visible    ${TILE_XONOTIC}    timeout=15s

    # Redireciona window.open() para a tab atual (headless não abre novas janelas)
    Execute Javascript    window.open = function(url, name, specs) { window.location.href = url; return window; };
    Click Element    ${TILE_XONOTIC}

    # Se a sessão já estiver ativa, o Moonlight exibe um menu de contexto com 'Resume Session'
    ${resume_visible}=    Run Keyword And Return Status
    ...    Wait Until Element Is Visible    xpath=//p[contains(@class, 'context-menu-element') and contains(text(), 'Resume Session')]    timeout=3s
    IF    ${resume_visible}
        Click Element    xpath=//p[contains(@class, 'context-menu-element') and contains(text(), 'Resume Session')]
    END

    ${STREAM_CANVAS}    Set Variable    css=video, canvas
    ${canvas_ok}=    Run Keyword And Return Status
    ...    Wait Until Element Is Visible    ${STREAM_CANVAS}    timeout=60s
    IF    not ${canvas_ok}
        Capture Page Screenshot    ${OUTPUT DIR}/debug_canvas_nao_encontrado.png
        ${page_url}=    Get Location
        Log To Console    [DEBUG] URL atual: ${page_url}
        ${page_src}=    Get Source
        Create File    ${OUTPUT DIR}/debug_page_source.html    ${page_src}
        Fail    Canvas/video não apareceu após 60s. Screenshot e HTML guardados para análise.
    END
    Set Focus To Element             ${STREAM_CANVAS}

    # 1. Clica no centro/esquerda do canvas (offset a partir do centro: x=-150, y=0)
    Click Element At Coordinates    ${STREAM_CANVAS}    -150    0
    Sleep    1s

    # 2. Pressiona ENTER para abrir o menu Singleplayer
    Press Keys    ${STREAM_CANVAS}    ENTER
    Sleep    2s

    # 3. Pressiona TAB para selecionar a opção 'Instant Action'
    Press Keys    ${STREAM_CANVAS}    TAB
    Sleep    1s

    # 4. Pressiona ENTER para começar a partida em mapa aleatório
    Press Keys    ${STREAM_CANVAS}    ENTER
    Log To Console    [INFO] Partida acionada (Instant Action). Aguardando 8s para carregamento do mapa...
    Sleep    8s

    # Ativa o painel de estatísticas (Stats) do Moonlight Web
    ${stats_btn_visible}=    Run Keyword And Return Status    Wait Until Element Is Visible    xpath=//button[text()='Stats']    timeout=5s
    IF    ${stats_btn_visible}
        Click Element    xpath=//button[text()='Stats']
    ELSE
        Run Keyword And Ignore Error    Click Element    id=sidebar-button
        Sleep    1s
        Run Keyword And Ignore Error    Click Element    xpath=//button[text()='Stats']
    END

    # Fecha a sidebar para não bloquear a visão nem reter o foco dos comandos
    Sleep    1s
    Run Keyword And Ignore Error    Click Element    id=sidebar-button

    # Garante que o painel .video-stats continue visível
    Execute Javascript    const s = document.querySelector('.video-stats'); if (s) { s.removeAttribute('hidden'); s.style.display='block'; }

    # Devolve o foco total ao jogo: clica no centro do canvas e foca no div #input (capturador de comandos do Moonlight)
    Click Element At Coordinates    ${STREAM_CANVAS}    0    0
    Run Keyword And Ignore Error    Set Focus To Element    id=input

    # Captura a tela do jogo com os stats ativos e a sidebar recolhida
    Capture Page Screenshot    ${OUTPUT DIR}/debug_partida_com_stats.png

    Log To Console    Streaming de vídeo a decorrer, a recolher latência e a enviar comandos...

    FOR    ${i}    IN RANGE    ${TEMPO_VIDEO}
        # Verifica se o streaming continua vivo
        ${canvas_vivo}=    Run Keyword And Return Status    Element Should Be Visible    ${STREAM_CANVAS}
        IF    not ${canvas_vivo}
            Capture Page Screenshot    ${OUTPUT DIR}/debug_streaming_perdeu_conexao.png
            Fail    Defeito detetado: O streaming de vídeo bloqueou ou a página perdeu a ligação!
        END

        # Extrai a linha exata de latência da rede (streamer to browser rtt)
        ${rtt_rede}=    Execute Javascript
        ...    const el = document.querySelector('.video-stats');
        ...    if (!el) return null;
        ...    const text = el.innerText || el.textContent || '';
        ...    const lines = text.split('\\n');
        ...    const found = lines.find(l => l.toLowerCase().includes('streamer to browser rtt'));
        ...    return found ? found.trim() : null;

        # Timestamp atual para registrar o momento exato de cada métrica
        ${data_hora}=    Get Current Date    result_format=%Y-%m-%d %H:%M:%S

        IF    $rtt_rede
            Append To File    ${LATENCY_FILE}    [${data_hora}] ${rtt_rede}${\n}
        ELSE
            Append To File    ${LATENCY_FILE}    [${data_hora}] streaming_ativo${\n}
        END

        ${multiplo_de_dez}=    Evaluate    ${i} % 10

        IF    ${multiplo_de_dez} == 0 and ${i} > 0
            # Envia teclas diretamente para o canvas e para o capturador de input
            Press Keys    ${STREAM_CANVAS}    W
            Press Keys    ${STREAM_CANVAS}    SPACE
        END

        Sleep    1s
    END

    Close All Browsers

Abrir Navegador Streaming
    ${options}=    Evaluate    sys.modules['selenium.webdriver'].ChromeOptions()    sys
    Evaluate    $options.add_argument("--headless=new")
    Evaluate    $options.add_argument("--no-sandbox")
    Evaluate    $options.add_argument("--disable-dev-shm-usage")
    Evaluate    $options.add_argument("--disable-gpu")
    Evaluate    $options.add_argument("--disable-popup-blocking")
    Evaluate    $options.add_argument("--disable-background-timer-throttling")
    Evaluate    $options.add_argument("--disable-renderer-backgrounding")
    Evaluate    $options.add_argument("--page-load-strategy=eager")
    Evaluate    $options.add_argument("--window-size=1920,1080")
    Evaluate    $options.add_argument("--mute-audio")
    Evaluate    $options.add_argument("--autoplay-policy=no-user-gesture-required")
    Evaluate    $options.add_argument("--ignore-certificate-errors")
    Evaluate    $options.add_argument("--no-first-run")
    Evaluate    $options.add_argument("--disable-extensions")

    Create Webdriver    Chrome    options=${options}
    Set Selenium Page Load Timeout    60 seconds
    Execute Javascript    Object.defineProperty(navigator, 'webdriver', {get: () => undefined})
