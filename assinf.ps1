[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Função para obter o Domínio/Grupo de Trabalho
function Get-DomainOrWorkgroup {
    try {
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
        if ($computerSystem.PartOfDomain) {
            $domainOrWorkgroup = "Domínio: "
            $name = $computerSystem.Domain
        } else {
            $domainOrWorkgroup = "Grupo de Trabalho: "
            $name = $computerSystem.Workgroup
        }
        
        # Exibir o texto fixo e o nome em amarelo
        Write-Host -NoNewline $domainOrWorkgroup
        Write-Host $name -ForegroundColor Yellow
    } catch {
        Write-Host "Erro ao obter o domínio ou grupo de trabalho: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Função para mostrar informações
function Mostrar-Informacoes {
    try {
        $ComputerName = (Get-CimInstance -ClassName Win32_ComputerSystem).Name
        $SupervisorConfigured = if (Get-LocalUser -Name "Supervisor" -ErrorAction SilentlyContinue) { "SIM" } else { "NÃO" }
        
        # Exibir a frase "Nome atual do computador: " e o nome do computador em ciano
        Write-Host -NoNewline "Nome atual do computador: "
        Write-Host $ComputerName -ForegroundColor Cyan
        
        # Exibir a frase com "Sim" em verde ou "Não" em vermelho
        Write-Host -NoNewline "Conta Supervisor configurada: "
        if ($SupervisorConfigured -eq "SIM") {
            Write-Host $SupervisorConfigured -ForegroundColor Green
        } else {
            Write-Host $SupervisorConfigured -ForegroundColor Red
        }

        Write-Host (Get-DomainOrWorkgroup)
        
        Start-Sleep -Seconds 3
    } catch {
        Write-Host "Erro ao mostrar informações: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Função para configurar as contas
function Configurar-Contas {
    try {
        Write-Host "Configurando a conta de Administrador..."

        # Ativar a conta de Administrador e configurar senha
        net user Administrador suporte1000 /active:yes | Out-Null
        Set-LocalUser -Name "Administrador" -PasswordNeverExpires $true | Out-Null
        Enable-LocalUser -Name "Administrador" | Out-Null

        Write-Host "Conta Administrador configurada com sucesso!" -ForegroundColor Green
        Start-Sleep -Seconds 1

        # Criar a conta de Supervisor
        Write-Host "Criando a conta de Supervisor..."
        net user Supervisor suporte1000 /add | Out-Null
        Set-LocalUser -Name "Supervisor" -PasswordNeverExpires $true | Out-Null
        Enable-LocalUser -Name "Supervisor" | Out-Null  # Garantir que a conta de Supervisor esteja ativa

        # Adicionar Supervisor ao grupo de Administradores
        Add-LocalGroupMember -Group "Administradores" -Member "Supervisor" | Out-Null

        Write-Host "Conta de Supervisor criada com sucesso!" -ForegroundColor Green
        Start-Sleep -Seconds 1

        # Mensagem final
        Write-Host "Configurações concluídas com sucesso!" -ForegroundColor Green
        Start-Sleep -Seconds 1

    } catch {
        Write-Host "Erro durante a configuração das contas. Detalhes: $($_.Exception.Message)" -ForegroundColor Red
    }

    # Aguardar o pressionamento de uma tecla para retornar ao menu principal
    Write-Host "Pressione qualquer tecla para voltar ao menu principal..." -ForegroundColor Yellow
    [System.Console]::ReadKey($true) | Out-Null

    # Retornar ao Menu Principal
    Menu
}

# Função para validar entrada de nome do computador
function Validate-ComputerName {
    param (
        [string]$ComputerName
    )
    if ($ComputerName -match '^[a-zA-Z0-9\-]{1,15}$') {
        return $true
    } else {
        Write-Host "Nome do computador inválido. Deve conter apenas letras, números e hífens, e ter no máximo 15 caracteres." -ForegroundColor Red
        return $false
    }
}

# Função para verificar conectividade com o domínio
function Test-DomainConnection {
    param (
        [string]$Domain
    )
    Write-Host "Verificando conectividade com o domínio..."
    return Test-Connection -ComputerName $Domain -Count 1 -Quiet
}

# Função para adicionar ao domínio
function Adicionar-Ao-Dominio {
    $ErrorActionPreference = "Stop"  # Colocando o PowerShell em modo para não fechar automaticamente

    try {
        Clear-Host

        # Obter o nome atual do computador
        $ComputerName = (Get-CimInstance -ClassName Win32_ComputerSystem).Name
        Write-Host -NoNewline "Nome atual do computador: "
        Write-Host $ComputerName -ForegroundColor Yellow

        # Loop para garantir que o nome do computador seja confirmado e válido
        do {
            do {
                $NewName = Read-Host "Digite o novo nome do computador"
            } while (-not (Validate-ComputerName -ComputerName $NewName))

            Write-Host "O novo nome do computador é: $NewName. Está correto? (Pressione 'S' para Sim ou 'N' para Não)"
            $UserChoice = [System.Console]::ReadKey($true).KeyChar
        } while ($UserChoice -ne 'S')

        # Definir o nome do domínio
        $Domain = "ppdf.df.gov.br"

        # Loop para solicitar login e senha até que sejam corretos
        do {
            # Solicitar o login e a senha do usuário
            $Username = Read-Host "Digite o seu nome de usuário"
            $PasswordPlain = Read-Host "Digite a sua senha" -AsSecureString
            $Credential = New-Object System.Management.Automation.PSCredential($Username, $PasswordPlain)

            Write-Host -NoNewline "Adicionando o computador ao domínio " -BackgroundColor Black
            Write-Host -NoNewline $Domain -ForegroundColor Yellow -BackgroundColor Black
            Write-Host -NoNewline " com o nome " -BackgroundColor Black
            Write-Host -NoNewline $NewName -ForegroundColor Yellow -BackgroundColor Black
            Write-Host "..." -BackgroundColor Black

            # Verificar a conectividade com o domínio
            if (Test-DomainConnection -Domain $Domain) {
                Write-Host "Conectado ao domínio!" -BackgroundColor DarkGreen
            } else {
               Write-Host "Não foi possível conectar ao domínio. Verifique a rede e tente novamente." -ForegroundColor Red
               continue
            }

            Write-Host "Verificando as credenciais..."

            # Testando a autenticação usando DirectorySearcher
            try {
                $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($PasswordPlain))
                $ldapPath = "LDAP://$Domain"
                $ldapUser = "$Domain\$Username"

                $DirectoryEntry = New-Object System.DirectoryServices.DirectoryEntry($ldapPath, $ldapUser, $password)
                $DirectorySearcher = New-Object System.DirectoryServices.DirectorySearcher($DirectoryEntry)
                $DirectorySearcher.Filter = "(samaccountname=$Username)"
                $SearchResult = $DirectorySearcher.FindOne()

                if ($SearchResult -ne $null) {
                    Write-Host "Credenciais corretas!" -BackgroundColor DarkGreen
                    $IsValid = $true
                } else {
                    Write-Host "Credenciais incorretas. Tente novamente." -ForegroundColor Red
                    $IsValid = $false
                }

            } catch {
                Write-Host "Erro ao validar as credenciais: $($_.Exception.Message)" -ForegroundColor Red
                $IsValid = $false
            }

        } until ($IsValid)

        # Adicionar o computador ao domínio
        try {
            Add-Computer -NewName $NewName -DomainName $Domain -Credential $Credential
            Write-Host "Computador adicionado ao domínio com sucesso!" -BackgroundColor DarkGreen
        } catch {
            Write-Host "Ocorreu um erro ao adicionar o computador ao domínio. Detalhes: $($_.Exception.Message)" -ForegroundColor Red
        }

        # Perguntar ao usuário se deseja reiniciar o computador agora
        Write-Host "Deseja reiniciar o computador agora? Pressione 'S' para "
        Write-Host -NoNewline "SIM" -ForegroundColor Green
        Write-Host -NoNewline " ou 'N' para "
        Write-Host "NÃO" -ForegroundColor Red
        $RestartChoice = [System.Console]::ReadKey($true).KeyChar

        if ($RestartChoice -eq 'S') {
            Write-Host "Reiniciando o computador em 10 segundos..." -ForegroundColor Green
            Start-Sleep -Seconds 10
            Restart-Computer
        } else {
            Write-Host "Reinicialização adiada. Não se esqueça de reiniciar o computador mais tarde." -ForegroundColor Yellow
            Write-Host "Pressione qualquer tecla para voltar ao menu principal..." -ForegroundColor Yellow
            [System.Console]::ReadKey($true) | Out-Null
            Menu
        }

    } catch {
        Write-Host "Erro fatal no script: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Detalhes do erro: $($_.Exception.StackTrace)" -ForegroundColor Yellow
        Start-Sleep -Seconds 5  # Aguarda para que o usuário veja o erro antes de sair
    } finally {
        # Garantindo que o script não feche automaticamente, e o usuário tenha tempo para ver a mensagem
        Write-Host "O script terminou. Pressione qualquer tecla para sair..."
        [System.Console]::ReadKey($true)
    }
}

# Função para remover do domínio
function Remover-Do-Dominio {
    $ErrorActionPreference = "Stop"  # Colocando o PowerShell em modo para não fechar automaticamente

    try {
        Clear-Host

        # Obter o nome atual do computador
        $ComputerName = (Get-CimInstance -ClassName Win32_ComputerSystem).Name
        Write-Host -NoNewline "Nome atual do computador: "
        Write-Host $ComputerName -ForegroundColor Yellow

        if ([string]::IsNullOrEmpty($ComputerName)) {
            throw "Nome do computador não pode ser nulo ou vazio."
        }

        # Definir o nome do domínio
        $Domain = "ppdf.df.gov.br"

        # Loop para solicitar login e senha até que sejam corretos
        do {
            # Solicitar o login e a senha do usuário
            $Username = Read-Host "Digite o seu nome de usuário"
            $PasswordPlain = Read-Host "Digite a sua senha" -AsSecureString
            $Credential = New-Object System.Management.Automation.PSCredential($Username, $PasswordPlain)

            # Verificar a conectividade com o domínio
            if (Test-DomainConnection -Domain $Domain) {
               Write-Host "Conectado ao domínio!" -BackgroundColor DarkGreen
            } else {
               Write-Host "Não foi possível conectar ao domínio. Verifique a rede e tente novamente." -ForegroundColor Red
               continue
            }

            Write-Host "Verificando as credenciais..."

            # Testando a autenticação usando DirectorySearcher
            try {
                $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($PasswordPlain))
                $ldapPath = "LDAP://$Domain"
                $ldapUser = "$Domain\$Username"

                $DirectoryEntry = New-Object System.DirectoryServices.DirectoryEntry($ldapPath, $ldapUser, $password)
                $DirectorySearcher = New-Object System.DirectoryServices.DirectorySearcher($DirectoryEntry)
                $DirectorySearcher.Filter = "(samaccountname=$Username)"
                $SearchResult = $DirectorySearcher.FindOne()

                if ($SearchResult -ne $null) {
                    Write-Host "Credenciais corretas!" -BackgroundColor DarkGreen
                    $IsValid = $true
                } else {
                    Write-Host "Credenciais incorretas. Tente novamente." -ForegroundColor Red
                    $IsValid = $false
                }

            } catch {
                Write-Host "Erro ao validar as credenciais: $($_.Exception.Message)" -ForegroundColor Red
                $IsValid = $false
            }

        } until ($IsValid)

        # Remover o computador do domínio
        try {
            $null = Remove-Computer -UnjoinDomainCredential $Credential -PassThru -Force
            Write-Host "Computador removido do domínio com sucesso!" -BackgroundColor DarkGreen
        } catch {
            Write-Host "Ocorreu um erro ao remover o computador do domínio. Detalhes: $($_.Exception.Message)" -ForegroundColor Red
        }

        # Perguntar ao usuário se deseja reiniciar o computador agora
        Write-Host "Deseja reiniciar o computador agora? Pressione 'S' para "
        Write-Host -NoNewline "SIM" -ForegroundColor Green
        Write-Host -NoNewline " ou 'N' para "
        Write-Host "NÃO" -ForegroundColor Red
        $RestartChoice = [System.Console]::ReadKey($true).KeyChar

        if ($RestartChoice -eq 'S') {
            Write-Host "Reiniciando o computador em 10 segundos..." -ForegroundColor Green
            Start-Sleep -Seconds 10
            Restart-Computer
        } else {
            Write-Host "Reinicialização adiada. Não se esqueça de reiniciar o computador mais tarde." -ForegroundColor Yellow
            Write-Host "Pressione qualquer tecla para voltar ao menu principal..." -ForegroundColor Yellow
            [System.Console]::ReadKey($true) | Out-Null
            Menu
        }

    } catch {
        Write-Host "Erro fatal no script: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Detalhes do erro: $($_.Exception.StackTrace)" -ForegroundColor Yellow
        Start-Sleep -Seconds 5  # Aguarda para que o usuário veja o erro antes de sair
    } finally {
        # Garantindo que o script não feche automaticamente, e o usuário tenha tempo para ver a mensagem
        Write-Host "O script terminou. Pressione qualquer tecla para sair..."
        [System.Console]::ReadKey($true)
    }
}

function Atualizar-Script {
    # URL do script atualizado
    $ScriptUrl = "https://raw.githubusercontent.com/Granadella/scriptassinf/main/assinf.ps1"
    
    # Verificar se o script está sendo executado de um arquivo
    if ($PSScriptRoot) {
        $ScriptLocal = Join-Path -Path $PSScriptRoot -ChildPath "assinf.ps1"  # Caminho completo do script atual
    } else {
        Write-Host "Erro: O caminho do script local não pôde ser determinado." -ForegroundColor Red
        return
    }

    try {
        Clear-Host
        Write-Host "Verificando por atualizações..." -ForegroundColor Cyan

        # Baixar o script atualizado para um arquivo temporário
        $TempFile = "$env:TEMP\script_atualizado.ps1"
        Invoke-WebRequest -Uri $ScriptUrl -OutFile $TempFile -UseBasicParsing -ErrorAction Stop

        # Reescrever o arquivo com a codificação UTF-8 com BOM
        $content = Get-Content -Path $TempFile -Raw
        [System.IO.File]::WriteAllText($TempFile, $content, [System.Text.Encoding]::UTF8)

        # Comparar o hash (opcional para verificar diferenças)
        $CurrentHash = Get-FileHash -Path $ScriptLocal -Algorithm SHA256
        $NewHash = Get-FileHash -Path $TempFile -Algorithm SHA256

        if ($CurrentHash.Hash -eq $NewHash.Hash) {
            Write-Host "O script já está atualizado!" -BackgroundColor DarkGreen
            Write-Host "Pressione qualquer tecla para voltar ao menu principal..." -ForegroundColor Yellow
            [System.Console]::ReadKey($true) | Out-Null
            Menu
        } else {
            Write-Host "Atualização disponível. Aplicando..." -ForegroundColor Yellow
            Copy-Item -Path $TempFile -Destination $ScriptLocal -Force
            Write-Host "Script atualizado com sucesso!" -BackgroundColor Green

            # Perguntar ao usuário se deseja reiniciar o script
            Write-Host "Deseja reiniciar o script agora? Pressione 'S' para SIM ou 'N' para NÃO." -ForegroundColor Yellow
            $RestartChoice = [System.Console]::ReadKey($true).KeyChar

            if ($RestartChoice -eq 'S') {
                Write-Host "Reiniciando o script..." -ForegroundColor Green
                Start-Process -FilePath "powershell.exe" -ArgumentList "-File `"$ScriptLocal`"" -NoNewWindow
                # Finalizar o script atual
                exit
            } else {
                Write-Host "Reinicialização adiada. Pressione qualquer tecla para voltar ao menu principal..." -ForegroundColor Yellow
                [System.Console]::ReadKey($true) | Out-Null
                Menu
            }
        }

        # Remover o arquivo temporário
        Remove-Item -Path $TempFile -Force

    } catch {
        Write-Host "Erro ao verificar ou aplicar a atualização: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Check-InvokeExpression {
    if ($env:FROM_WEB -eq "true") {
        Write-Host "Aviso: O script foi chamado via irm e iex. A função de verificar atualizações não estará disponível." -BackgroundColor DarkRed
        return $true
    }
    return $false
}

# Menu principal
function Menu {
    Clear-Host
    Write-Host "==============================="
    Write-Host "             PPDF              " -BackgroundColor DarkGray
    Write-Host "      FORTIS BRACHIUM LEGIS    " -ForegroundColor Yellow
    Write-Host "==============================="
    Write-Host "          CIR - ASSINF         "
    Write-Host "                               "
    Write-Host "         MENU PRINCIPAL        "
    Write-Host "==============================="
    Write-Host ""
    
    # Mostrar informações do sistema
    Mostrar-Informacoes

    # Verificar se o script foi chamado via irm e iex
    $disableUpdateCheck = Check-InvokeExpression

    Write-Host "==============================="
    Write-Host -NoNewline "1 - "
    Write-Host "Configurar contas;" -ForegroundColor Yellow
    Write-Host -NoNewline "2 - "
    Write-Host "Adicionar ao domínio;" -ForegroundColor Yellow
    Write-Host -NoNewline "3 - "
    Write-Host "Remover do domínio;" -ForegroundColor Yellow
    
    if (-not $disableUpdateCheck) {
        Write-Host -NoNewline "4 - "
        Write-Host "Verificar atualizações;" -ForegroundColor Yellow
    } else {
        Write-Host -NoNewline "4 - "
        Write-Host "Opção desativada;" -ForegroundColor Red
    }
    
    Write-Host -NoNewline "5 - "
    Write-Host "Sair." -ForegroundColor Yellow
    Write-Host ""

    Write-Host "Escolha uma opção (Pressione 1, 2, 3, 4 ou 5):"
    
    # Usar ReadKey para capturar a tecla pressionada
    $Escolha = [System.Console]::ReadKey($true).KeyChar
    
    switch ($Escolha) {
        '1' { Configurar-Contas }
        '2' { Adicionar-Ao-Dominio }
        '3' { Remover-Do-Dominio }
        '4' { if (-not $disableUpdateCheck) { Atualizar-Script } else { Clear-Host; Write-Host "Opção desativada." -ForegroundColor Red; Start-Sleep -Seconds 1; Menu } }
        '5' { Write-Host "Saindo..." -ForegroundColor Yellow; Exit }
        default { Write-Host "Opção inválida. Tente novamente." -ForegroundColor Red; Start-Sleep -Seconds 1; Menu }
    }
}

# Chamar o menu
Menu
