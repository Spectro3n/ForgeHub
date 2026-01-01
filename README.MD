# ForgeHub Ultimate v23.1 - Estrutura Modular

## 📁 Estrutura de Arquivos

```
ForgeHub/
├── main.lua                    # Carregador principal
├── core/
│   └── performance.lua        # Sistema de performance
├── semantic/
│   └── semantic.lua           # Engine semântico
├── esp/
│   └── esp.lua                # Sistema de ESP/Visuals
├── aimbot/
│   └── aimbot.lua            # Sistema de mira
└── ui/
    └── ui.lua                 # Interface Rayfield
```

## 🚀 Como Usar

### Opção 1: Carregar do GitHub (Recomendado)

1. **Faça upload dos arquivos para seu repositório GitHub**
   - Mantenha a estrutura de pastas
   - Exemplo: `https://raw.githubusercontent.com/seu_usuario/ForgeHub/main/`

2. **Edite o main.lua**
   - Linha 90: Altere `BASE_URL` para seu repositório:
   ```lua
   local BASE_URL = "https://raw.githubusercontent.com/SEU_USUARIO/ForgeHub/main/"
   ```

3. **Execute no Roblox**
   ```lua
   loadstring(game:HttpGet('https://raw.githubusercontent.com/SEU_USUARIO/ForgeHub/main/main.lua'))()
   ```

### Opção 2: Teste Local (Desenvolvimento)

Para testar localmente, você pode concatenar todos os arquivos ou usar o script combinado.

## 🎯 Funcionalidades

### ✅ Correções da v23.1
- **Box 2D**: Resíduos visuais corrigidos
- **ESP**: Todos elementos funcionando perfeitamente
- **Aimbot**: Lock menos "grudento" e mais responsivo

### 🔧 Sistemas Principais

#### Performance Manager
- Detecção automática de FPS
- Ajuste dinâmico de qualidade
- Drawing pool otimizado
- Cache de raycast por frame

#### Semantic Engine
- Detecção automática de times
- Aprendizado de entidades
- Scan incremental de containers
- Cache inteligente de players

#### ESP System
- Box 2D com cache otimizado
- Skeleton dinâmico (R6/R15)
- Health bars
- Nomes e distâncias
- Highlights (Chams)

#### Aimbot System
- Lock adaptativo
- Predição de movimento
- FOV circle
- Suavização legit
- Múltiplos métodos (Camera/MouseMoveRel)

#### UI System
- Interface Rayfield moderna
- Estatísticas em tempo real
- Configurações completas
- Sistema de notificações

## ⚙️ Configuração

### Atalhos Padrão
- **Q**: Toggle Aimbot
- **MouseButton2** (Botão direito): Ativar mira
- **K**: Abrir/Fechar menu

### Configurações Recomendadas

**Para Legit:**
- Suavização: 8-15
- FOV: 100-200
- Predição: Ativada (0.135)
- Visible Check: Ativado

**Para Rage:**
- Suavização: 0-3
- FOV: 500+
- Predição: Ativada (0.15+)
- Visible Check: Desativado

## 📊 Sistema de Performance

O ForgeHub ajusta automaticamente a qualidade baseado no FPS:

- **60+ FPS**: Qualidade máxima
- **45-60 FPS**: Qualidade reduzida
- **30-45 FPS**: Modo economia
- **<30 FPS**: Modo pânico (mínimo)

## 🔍 Sistema de Times

Detecta automaticamente:
- Roblox Teams nativo
- Atributos customizados
- FFA (Free-For-All)

## 🛠️ Desenvolvimento

### Modificar Módulos

Cada módulo é independente e pode ser editado separadamente:

**Adicionar nova funcionalidade ao ESP:**
```lua
-- Em esp/esp.lua
function ESP:MinhaNovaFuncao()
    -- Seu código
end
```

**Modificar configurações:**
```lua
-- Em main.lua, seção GLOBAL SETTINGS
Settings.MinhaConfiguracao = valor
```

### Debug

O sistema possui logs de erro automáticos:
```lua
-- Ver últimos erros
print(_G.ForgeHubCore.ErrorLog.LastErrors)
```

## ⚠️ Avisos

1. **Não modifique** a ordem de carregamento dos módulos
2. **Sempre teste** em servidor privado primeiro
3. **Mantenha** os nomes dos arquivos exatamente como estão
4. **Certifique-se** que todos os URLs estão corretos

## 📝 Changelog v23.1

### Correções
- ✅ Box 2D não deixa mais resíduos visuais
- ✅ ESP renderiza todos elementos corretamente
- ✅ Aimbot lock menos "grudento" (threshold 0.8)
- ✅ MaxLockTime reduzido para 1.5s

### Melhorias
- ✅ Arquitetura modular completa
- ✅ Cache de box otimizado
- ✅ Skeleton system melhorado
- ✅ Performance manager aprimorado

## 🤝 Suporte

Se encontrar bugs ou tiver sugestões:
1. Verifique se todos os módulos foram carregados
2. Confira o console (F9) para erros
3. Teste em diferentes jogos

## 📜 Licença

Este projeto é apenas para fins educacionais. Use por sua própria conta e risco.

---

**ForgeHub Ultimate v23.1** - Sistema de Aimbot & ESP Modular
Desenvolvido com arquitetura escalável e performance otimizada.