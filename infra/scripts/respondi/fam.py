import re
def familia(nome):
    n=nome.lower()
    if re.search(r'nps|vota[cç]|csat|teste|c[oó]pia|apostila|resumo|arquivo secreto|feedback|sorteio|desfazer|activecamp|patroc|rateio|leads|d[uú]vida|hot seat|tema|indica[cç][aã]o tema|me conta|coisa mais importante|refinamento|compartilhamento|artigos|monitores|oab',n): return None
    if re.search(r'coleta de opini|pesquisa inicial|briefing|pesquisa com os alunos|dados dos alunos antes',n): return 'questionario_inicial'
    if re.search(r'n[ií]ve(is|l)|galeria|ingressa no diamante|renova[cç]',n): return 'nivel'
    if re.search(r's[oó]cios',n): return 'socios'
    if re.search(r'envio kit|escrit[oó]rio|cnpj|dados\(|dados \(|\] dados|dados dos participantes|camisa|voo',n): return 'cadastro'
    if re.search(r'pesquisa de resultados|pesquisa final|debriefing|experi[eê]ncia|reuni[oõ]es de acelera|dificuldade|interesse',n): return 'pesquisa'
    if re.search(r'inscri|encontro|cl[ií]nica|workshop|palestra|webn|reserva|residen|imers|aula|aplica|participa|congresso|oficina|treinamento|holding \+|ht|consultoria|sess[aã]o',n): return 'evento'
    return 'outros'
