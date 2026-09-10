# TouchFlow — um plugin do Omarchy pra domar seu touchpad

Seu gesto de quatro dedos tinha um problema de autoestima: da Lua importante
no `input.lua`, os dois scripts bash gordinhos (`gesture-maximize.sh`,
`gesture-restore.sh`) e a função `navigate_skipping_empty()` que você passou a
madrugada ajustando.

TouchFlow troca esse besteirol todo por **um serviço** que olha o Hyprland ao
vivo (sem cafofilar `hyprctl | jq` a cada gesto) e faz tudo sozinho. Bônus de
caracter: quando não existe janela pra mexer, o gesto ainda é útil — abre o
menu de apps ou um terminal em vez de ficar parado feito tela de loading.

## Como funciona (arquitetura em 50 palavras)

O touchpad é ciumento e só fala com o compositor. Quem sente o swipe de quatro
dedos é o **Hyprland**, então o gatilho continua morando no `input.lua` — mas
só como "sensor": ele apenas telefona pro plugin via IPC e o plugin decide o
que fazer.

```
seu dedo -> Hyprland (input.lua) -> omarchy-shell touchflow <acao> ->  TouchFlow
                                  (só registra o gesto)             (raciocina e age)
```

## Instalação

1. Clone o repo direto na pasta de plugins do Omarchy:

   ```sh
   git clone https://github.com/nagualcode/touchflow.git \
     ~/.config/omarchy/plugins/touchflow
   ```

2. Habilite o plugin:

   ```sh
   omarchy-shell shell setPluginEnabled touchflow true
   ```

3. Dê um sacode no shell pra ele acordar com o novo colega de quarto:

   ```sh
   pkill -x quickshell
   ```

   (o launcher do Omarchy vigia e reinicia sozinho, pode soltar.)

4. Confirme que a coisa está viva:

   ```sh
   omarchy-shell touchflow state
   ```

   Se responder algo como `active=0 workspaces=1`, é sinal de vida.

## Colocando seu input.lua pra trabalhar

Deleta o bloco inteiro de Lua (a `navigate_skipping_empty`, os quatro
`hl.gesture` apontando pra scripts) e coloca só isto no lugar:

```lua
-- TouchFlow: o gesto só acorda o plugin; a decisão mora lá dentro.
hl.gesture({
  fingers = 4,
  direction = "left",
  action = function() hl.exec_cmd("omarchy-shell touchflow next") end,
})

hl.gesture({
  fingers = 4,
  direction = "right",
  action = function() hl.exec_cmd("omarchy-shell touchflow prev") end,
})

hl.gesture({
  fingers = 4,
  direction = "up",
  action = function() hl.exec_cmd("omarchy-shell touchflow up") end,
})

hl.gesture({
  fingers = 4,
  direction = "down",
  action = function() hl.exec_cmd("omarchy-shell touchflow down") end,
})
```

Pronto: de dezenas de linhas de Lua + dois scripts pra quatro telefonemas.

## O que cada gesto faz

| Gesto | Sem janela / ws vazio | Várias janelas | Uma janela sozinha |
| --- | --- | --- | --- |
| **Cima** | abre o menu de apps | move a janela ativa pro 1º ws vazio (ou cria um novo) | move pro próximo ws, **somente** se ele estiver ocupado |
| **Baixo** | abre o terminal (foot) | move a janela ativa um ws pra esquerda | idem |
| **Esquerda** | — | pula pro próximo ws ocupado, ignorando buracos vazios | idem, garantindo um ws fresco logo após o último usado |
| **Direita** | — | idem, pro lado contrário | idem |

Detalhes finos:

- Swipe pra **cima** com uma janela sozinha só move se o vizinho da direita
  tiver gente; se o vizinho estiver vazio, ninguém se mexe (teletransporte
  desnecessário é falta de educação).
- Swipe pra **baixo** já no workspace 1 não faz nada — não existe esquerda do 1.
- Swipe **lateral** sempre ignora os buracos: workspaces vazios são pulados e
  um novo aparece logo depois do último usado, pronto pra receber coisa.

## IPC: funciona de qualquer lugar

Não precisa ser gesto — pode chamar de atalho, de bar, de script:

```sh
omarchy-shell touchflow up      # agir como swipe pra cima
omarchy-shell touchflow down    # agir como swipe pra baixo
omarchy-shell touchflow next    # pular pro próximo ws ocupado
omarchy-shell touchflow prev    # pular pro anterior
omarchy-shell touchflow state   # diagnóstico rápido
```

## FAQ — "deu errado" (e como desmentir)

- **"Nada acontece no swipe."**
  Confirme que o plugin está no time: `omarchy-shell shell listPlugins | grep touchflow`
  deve mostrar `touchflow` com `enabled`. Depois teste o elo sozinho:
  `omarchy-shell touchflow state`. Se responder, o problema está no `input.lua`
  (direção errada, `hl.exec_cmd` fora do lugar).
- **"Abriu menu quando eu ia abrir terminal."**
  Comportamento esperado: sem janela, swipe-cima chama o menu e swipe-baixo
  chama o terminal. Acerte a direção do dedo, não o plugin.
- **"Quero outro terminal no lugar do foot."**
  Uma linha mágica no `Touchflow.qml`, função `openTerminal()`.
- **"O plugin reinicia sem parar."**
  Regra de ouro: **nunca** crie/grave arquivos dentro da pasta do plugin.
  O Omarchy observa essa pasta pra recarregar plugins na hora, e escrever
  dentro dela dispara um loop eterno de reloads (sim, aprendemos do jeito
  difícil, e o `click.log` é o nosso mártir).

## Licença

MIT. Os dedos agradecem.