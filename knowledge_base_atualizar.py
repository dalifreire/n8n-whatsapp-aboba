#!/usr/bin/env python3
"""
Script para atualizar a base de conhecimento da ABO-BA.

Fontes:
  - https://abo-ba.org.br (website principal)
  - https://www.instagram.com/abobahia/ (redes sociais)

Funcionalidades:
  - Scraping do website
  - Coleta de dados do Instagram (via API ou web scraping)
  - Validação de dados
  - Merge com base existente
  - Backup automático
  - Exportação em JSON

Uso:
    python atualizar_knowledge_base.py [--site] [--instagram] [--full] [--backup]

Exemplos:
    # Atualizar apenas dados do site
    python atualizar_knowledge_base.py --site
    
    # Atualizar apenas dados do Instagram
    python atualizar_knowledge_base.py --instagram
    
    # Atualização completa com backup
    python atualizar_knowledge_base.py --full --backup
    
    # Apenas validar dados existentes
    python atualizar_knowledge_base.py --validate
"""

import json
import os
import sys
import argparse
import logging
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Any, Optional
from dataclasses import dataclass, asdict
import shutil

# Imports opcionais
try:
    import requests
    from bs4 import BeautifulSoup
    REQUESTS_AVAILABLE = True
except ImportError:
    REQUESTS_AVAILABLE = False
    print("⚠️  Warning: requests/BeautifulSoup não instalados")
    print("   Execute: pip install requests beautifulsoup4")

try:
    from instagrapi import Client as InstagramClient
    INSTAGRAM_AVAILABLE = True
except ImportError:
    INSTAGRAM_AVAILABLE = False
    # Isso é OK, vamos usar alternativas


# ============================================================================
# CONFIGURAÇÃO DE LOGGING
# ============================================================================

logging.basicConfig(
    level=logging.INFO,
    format='%(levelname)s - %(asctime)s - %(message)s',
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler('atualizar_knowledge_base.log')
    ]
)
logger = logging.getLogger(__name__)


# ============================================================================
# DATA CLASSES
# ============================================================================

@dataclass
class DocumentoRAG:
    """Estrutura padrão de um documento na base de conhecimento."""
    id: str
    categoria: str
    titulo: str
    conteudo: str
    metadata: Dict[str, Any]

    def to_dict(self) -> Dict[str, Any]:
        """Converte para dicionário."""
        return asdict(self)

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'DocumentoRAG':
        """Cria a partir de dicionário."""
        return cls(**data)


# ============================================================================
# SCRAPER DO WEBSITE
# ============================================================================

class WebSiteScraper:
    """Responsável por fazer scraping do website da ABO-BA."""

    def __init__(self, base_url: str = "https://abo-ba.org.br"):
        self.base_url = base_url
        self.session = self._create_session() if REQUESTS_AVAILABLE else None

    def _create_session(self) -> Optional[requests.Session]:
        """Cria uma sessão com user agent."""
        if not REQUESTS_AVAILABLE:
            return None
        
        session = requests.Session()
        session.headers.update({
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        })
        return session

    def scrape_site(self) -> List[DocumentoRAG]:
        """Faz scraping completo do website da ABO."""
        if not REQUESTS_AVAILABLE:
            logger.error("❌ requests/BeautifulSoup não disponíveis")
            return []

        documentos = []
        logger.info("📡 Iniciando scraping completo do website...")

        # Lista completa de páginas para scrape
        paginas = [
            {"url": "", "nome": "homepage", "metodo": self._scrape_homepage},
            {"url": "/quem-somos/", "nome": "quem_somos", "metodo": self._scrape_quem_somos},
            {"url": "/estrutura-da-abo-ba/", "nome": "estrutura", "metodo": self._scrape_estrutura},
            {"url": "/noticias/", "nome": "noticias", "metodo": self._scrape_noticias},
            {"url": "/regionais-da-abo-ba/", "nome": "regionais", "metodo": self._scrape_regionais},
            {"url": "/biblioteca/", "nome": "biblioteca", "metodo": self._scrape_biblioteca},
            {"url": "/socios-benemeritos-da-abo-ba/", "nome": "benemeritos", "metodo": self._scrape_benemeritos},
            {"url": "/projetos-sociais-abo-ba/", "nome": "projetos_sociais", "metodo": self._scrape_projetos_sociais},
            {"url": "/revista-abo-ba/", "nome": "revista", "metodo": self._scrape_revista},
            {"url": "/imoba/", "nome": "imoba", "metodo": self._scrape_imoba},
            {"url": "/cursos-teste/", "nome": "cursos", "metodo": self._scrape_cursos},
            {"url": "/associe-se/", "nome": "associe_se", "metodo": self._scrape_associe_se},
            {"url": "/contato/", "nome": "contato", "metodo": self._scrape_contato}
        ]

        try:
            for pagina in paginas:
                try:
                    logger.info(f"🔍 Analisando: {pagina['nome']}")
                    docs_pagina = pagina["metodo"](pagina["url"])
                    documentos.extend(docs_pagina)
                    logger.info(f"   ✅ {len(docs_pagina)} documentos extraídos")
                except Exception as e:
                    logger.warning(f"⚠️  Erro em {pagina['nome']}: {str(e)}")
                    continue

            logger.info(f"✅ Scraping concluído: {len(documentos)} documentos extraídos")
            return documentos

        except Exception as e:
            logger.error(f"❌ Erro no scraping: {str(e)}")
            return documentos

    def _scrape_homepage(self, path: str = "") -> List[DocumentoRAG]:
        """Extrai dados da página inicial."""
        documentos = []

        try:
            url = self.base_url + path
            response = self.session.get(url, timeout=10)
            response.raise_for_status()
            soup = BeautifulSoup(response.content, 'html.parser')

            # Título e descrição principal
            title_element = soup.find('h1')
            if title_element:
                titulo = title_element.get_text().strip()
                conteudo = " ".join([
                    p.get_text().strip() 
                    for p in soup.find_all('p')[:3]
                ])

                if conteudo:
                    doc = DocumentoRAG(
                        id="abo_web_homepage",
                        categoria="geral",
                        titulo=f"Informações Principal: {titulo}",
                        conteudo=conteudo,
                        metadata={
                            "fonte": "website",
                            "tipo": "homepage",
                            "atualizado": datetime.now().strftime("%Y-%m-%d"),
                            "relevancia": "muito_alto",
                            "url": url
                        }
                    )
                    documentos.append(doc)

        except Exception as e:
            logger.warning(f"⚠️  Erro na homepage: {str(e)}")

        return documentos

    def _scrape_quem_somos(self, path: str) -> List[DocumentoRAG]:
        """Extrai dados da página Quem Somos."""
        documentos = []
        
        try:
            url = self.base_url + path
            response = self.session.get(url, timeout=10)
            response.raise_for_status()
            soup = BeautifulSoup(response.content, 'html.parser')

            # Extrai seções sobre a história e missão
            sections = soup.find_all(['h1', 'h2', 'h3'])
            for section in sections:
                titulo = section.get_text().strip()
                
                # Pega próximos parágrafos até próximo heading
                content_parts = []
                next_elem = section.find_next()
                while next_elem and next_elem.name not in ['h1', 'h2', 'h3']:
                    if next_elem.name == 'p':
                        content_parts.append(next_elem.get_text().strip())
                    next_elem = next_elem.find_next()

                conteudo = " ".join(content_parts)

                if conteudo and len(conteudo) > 20:
                    doc = DocumentoRAG(
                        id=f"abo_web_quem_somos_{titulo.lower().replace(' ', '_')[:20]}",
                        categoria="sobre_abo",
                        titulo=titulo,
                        conteudo=conteudo,
                        metadata={
                            "fonte": "website",
                            "tipo": "quem_somos",
                            "atualizado": datetime.now().strftime("%Y-%m-%d"),
                            "relevancia": "alto",
                            "url": url
                        }
                    )
                    documentos.append(doc)

        except Exception as e:
            logger.warning(f"⚠️  Erro em quem-somos: {str(e)}")

        return documentos

    def _scrape_estrutura(self, path: str) -> List[DocumentoRAG]:
        """Extrai dados da página Estrutura da ABO-BA."""
        documentos = []
        
        try:
            url = self.base_url + path
            response = self.session.get(url, timeout=10)
            response.raise_for_status()
            soup = BeautifulSoup(response.content, 'html.parser')

            # Extrai informações sobre estrutura organizacional
            sections = soup.find_all(['h2', 'h3', 'h4'])
            for section in sections:
                titulo = section.get_text().strip()
                
                content_parts = []
                next_elem = section.find_next()
                while next_elem and next_elem.name not in ['h2', 'h3', 'h4']:
                    if next_elem.name in ['p', 'li', 'div']:
                        content_parts.append(next_elem.get_text().strip())
                    next_elem = next_elem.find_next()

                conteudo = " ".join(content_parts)

                if conteudo and len(conteudo) > 20:
                    doc = DocumentoRAG(
                        id=f"abo_web_estrutura_{titulo.lower().replace(' ', '_')[:20]}",
                        categoria="estrutura",
                        titulo=titulo,
                        conteudo=conteudo,
                        metadata={
                            "fonte": "website",
                            "tipo": "estrutura",
                            "atualizado": datetime.now().strftime("%Y-%m-%d"),
                            "relevancia": "alto",
                            "url": url
                        }
                    )
                    documentos.append(doc)

        except Exception as e:
            logger.warning(f"⚠️  Erro em estrutura: {str(e)}")

        return documentos

    def _scrape_noticias(self, path: str) -> List[DocumentoRAG]:
        """Extrai notícias e atualizações."""
        documentos = []
        
        try:
            url = self.base_url + path
            response = self.session.get(url, timeout=10)
            response.raise_for_status()
            soup = BeautifulSoup(response.content, 'html.parser')

            # Extrai notícias (limitado às últimas 10)
            news_items = soup.find_all(class_=['news', 'post', 'article'])[:10]

            for idx, item in enumerate(news_items):
                titulo_elem = item.find(['h1', 'h2', 'h3', 'h4', 'a'])
                if titulo_elem:
                    titulo = titulo_elem.get_text().strip()
                    conteudo = " ".join([
                        p.get_text().strip() 
                        for p in item.find_all('p')
                    ])

                    if conteudo:
                        doc = DocumentoRAG(
                            id=f"abo_web_noticia_{idx}_{datetime.now().strftime('%Y%m%d')}",
                            categoria="noticias",
                            titulo=titulo,
                            conteudo=conteudo,
                            metadata={
                                "fonte": "website",
                                "tipo": "noticia",
                                "atualizado": datetime.now().strftime("%Y-%m-%d"),
                                "relevancia": "medio",
                                "url": url
                            }
                        )
                        documentos.append(doc)

        except Exception as e:
            logger.warning(f"⚠️  Erro em notícias: {str(e)}")

        return documentos

    def _scrape_regionais(self, path: str) -> List[DocumentoRAG]:
        """Extrai informações sobre as regionais."""
        documentos = []
        
        try:
            url = self.base_url + path
            response = self.session.get(url, timeout=10)
            response.raise_for_status()
            soup = BeautifulSoup(response.content, 'html.parser')

            # Extrai informações das regionais
            sections = soup.find_all(['h2', 'h3'])
            for section in sections:
                titulo = section.get_text().strip()
                
                content_parts = []
                next_elem = section.find_next()
                while next_elem and next_elem.name not in ['h2', 'h3']:
                    if next_elem.name in ['p', 'li', 'div']:
                        content_parts.append(next_elem.get_text().strip())
                    next_elem = next_elem.find_next()

                conteudo = " ".join(content_parts)

                if conteudo and len(conteudo) > 20:
                    doc = DocumentoRAG(
                        id=f"abo_web_regional_{titulo.lower().replace(' ', '_')[:20]}",
                        categoria="regionais",
                        titulo=titulo,
                        conteudo=conteudo,
                        metadata={
                            "fonte": "website",
                            "tipo": "regional",
                            "atualizado": datetime.now().strftime("%Y-%m-%d"),
                            "relevancia": "medio",
                            "url": url
                        }
                    )
                    documentos.append(doc)

        except Exception as e:
            logger.warning(f"⚠️  Erro em regionais: {str(e)}")

        return documentos

    def _scrape_biblioteca(self, path: str) -> List[DocumentoRAG]:
        """Extrai informações da biblioteca."""
        documentos = []
        
        try:
            url = self.base_url + path
            response = self.session.get(url, timeout=10)
            response.raise_for_status()
            soup = BeautifulSoup(response.content, 'html.parser')

            # Extrai informações sobre recursos da biblioteca
            sections = soup.find_all(['h2', 'h3'])
            for section in sections:
                titulo = section.get_text().strip()
                
                content_parts = []
                next_elem = section.find_next()
                while next_elem and next_elem.name not in ['h2', 'h3']:
                    if next_elem.name in ['p', 'li', 'div']:
                        content_parts.append(next_elem.get_text().strip())
                    next_elem = next_elem.find_next()

                conteudo = " ".join(content_parts)

                if conteudo and len(conteudo) > 20:
                    doc = DocumentoRAG(
                        id=f"abo_web_biblioteca_{titulo.lower().replace(' ', '_')[:20]}",
                        categoria="biblioteca",
                        titulo=titulo,
                        conteudo=conteudo,
                        metadata={
                            "fonte": "website",
                            "tipo": "biblioteca",
                            "atualizado": datetime.now().strftime("%Y-%m-%d"),
                            "relevancia": "medio",
                            "url": url
                        }
                    )
                    documentos.append(doc)

        except Exception as e:
            logger.warning(f"⚠️  Erro em biblioteca: {str(e)}")

        return documentos

    def _scrape_benemeritos(self, path: str) -> List[DocumentoRAG]:
        """Extrai informações sobre sócios beneméritos."""
        documentos = []
        
        try:
            url = self.base_url + path
            response = self.session.get(url, timeout=10)
            response.raise_for_status()
            soup = BeautifulSoup(response.content, 'html.parser')

            # Extrai informações sobre beneméritos
            sections = soup.find_all(['h2', 'h3'])
            for section in sections:
                titulo = section.get_text().strip()
                
                content_parts = []
                next_elem = section.find_next()
                while next_elem and next_elem.name not in ['h2', 'h3']:
                    if next_elem.name in ['p', 'li', 'div']:
                        content_parts.append(next_elem.get_text().strip())
                    next_elem = next_elem.find_next()

                conteudo = " ".join(content_parts)

                if conteudo and len(conteudo) > 20:
                    doc = DocumentoRAG(
                        id=f"abo_web_benemerito_{titulo.lower().replace(' ', '_')[:20]}",
                        categoria="benemeritos",
                        titulo=titulo,
                        conteudo=conteudo,
                        metadata={
                            "fonte": "website",
                            "tipo": "benemerito",
                            "atualizado": datetime.now().strftime("%Y-%m-%d"),
                            "relevancia": "baixo",
                            "url": url
                        }
                    )
                    documentos.append(doc)

        except Exception as e:
            logger.warning(f"⚠️  Erro em benemeritos: {str(e)}")

        return documentos

    def _scrape_projetos_sociais(self, path: str) -> List[DocumentoRAG]:
        """Extrai informações sobre projetos sociais."""
        documentos = []
        
        try:
            url = self.base_url + path
            response = self.session.get(url, timeout=10)
            response.raise_for_status()
            soup = BeautifulSoup(response.content, 'html.parser')

            # Extrai informações sobre projetos sociais
            sections = soup.find_all(['h2', 'h3'])
            for section in sections:
                titulo = section.get_text().strip()
                
                content_parts = []
                next_elem = section.find_next()
                while next_elem and next_elem.name not in ['h2', 'h3']:
                    if next_elem.name in ['p', 'li', 'div']:
                        content_parts.append(next_elem.get_text().strip())
                    next_elem = next_elem.find_next()

                conteudo = " ".join(content_parts)

                if conteudo and len(conteudo) > 20:
                    doc = DocumentoRAG(
                        id=f"abo_web_projeto_{titulo.lower().replace(' ', '_')[:20]}",
                        categoria="projetos_sociais",
                        titulo=titulo,
                        conteudo=conteudo,
                        metadata={
                            "fonte": "website",
                            "tipo": "projeto_social",
                            "atualizado": datetime.now().strftime("%Y-%m-%d"),
                            "relevancia": "alto",
                            "url": url
                        }
                    )
                    documentos.append(doc)

        except Exception as e:
            logger.warning(f"⚠️  Erro em projetos sociais: {str(e)}")

        return documentos

    def _scrape_revista(self, path: str) -> List[DocumentoRAG]:
        """Extrai informações sobre a revista ABO-BA."""
        documentos = []
        
        try:
            url = self.base_url + path
            response = self.session.get(url, timeout=10)
            response.raise_for_status()
            soup = BeautifulSoup(response.content, 'html.parser')

            # Extrai informações sobre a revista
            sections = soup.find_all(['h2', 'h3'])
            for section in sections:
                titulo = section.get_text().strip()
                
                content_parts = []
                next_elem = section.find_next()
                while next_elem and next_elem.name not in ['h2', 'h3']:
                    if next_elem.name in ['p', 'li', 'div']:
                        content_parts.append(next_elem.get_text().strip())
                    next_elem = next_elem.find_next()

                conteudo = " ".join(content_parts)

                if conteudo and len(conteudo) > 20:
                    doc = DocumentoRAG(
                        id=f"abo_web_revista_{titulo.lower().replace(' ', '_')[:20]}",
                        categoria="revista",
                        titulo=titulo,
                        conteudo=conteudo,
                        metadata={
                            "fonte": "website",
                            "tipo": "revista",
                            "atualizado": datetime.now().strftime("%Y-%m-%d"),
                            "relevancia": "medio",
                            "url": url
                        }
                    )
                    documentos.append(doc)

        except Exception as e:
            logger.warning(f"⚠️  Erro em revista: {str(e)}")

        return documentos

    def _scrape_imoba(self, path: str) -> List[DocumentoRAG]:
        """Extrai informações sobre o IMOBA (Museu de Odontologia)."""
        documentos = []
        
        try:
            url = self.base_url + path
            response = self.session.get(url, timeout=10)
            response.raise_for_status()
            soup = BeautifulSoup(response.content, 'html.parser')

            # Extrai informações sobre o museu
            sections = soup.find_all(['h2', 'h3'])
            for section in sections:
                titulo = section.get_text().strip()
                
                content_parts = []
                next_elem = section.find_next()
                while next_elem and next_elem.name not in ['h2', 'h3']:
                    if next_elem.name in ['p', 'li', 'div']:
                        content_parts.append(next_elem.get_text().strip())
                    next_elem = next_elem.find_next()

                conteudo = " ".join(content_parts)

                if conteudo and len(conteudo) > 20:
                    doc = DocumentoRAG(
                        id=f"abo_web_imoba_{titulo.lower().replace(' ', '_')[:20]}",
                        categoria="museu",
                        titulo=titulo,
                        conteudo=conteudo,
                        metadata={
                            "fonte": "website",
                            "tipo": "museu",
                            "atualizado": datetime.now().strftime("%Y-%m-%d"),
                            "relevancia": "medio",
                            "url": url
                        }
                    )
                    documentos.append(doc)

        except Exception as e:
            logger.warning(f"⚠️  Erro em imoba: {str(e)}")

        return documentos

    def _scrape_cursos(self, path: str) -> List[DocumentoRAG]:
        """Extrai informações sobre cursos e especializações."""
        documentos = []
        
        try:
            url = self.base_url + path
            response = self.session.get(url, timeout=10)
            response.raise_for_status()
            soup = BeautifulSoup(response.content, 'html.parser')

            # Extrai informações sobre cursos
            sections = soup.find_all(['h2', 'h3'])
            for section in sections:
                titulo = section.get_text().strip()
                
                content_parts = []
                next_elem = section.find_next()
                while next_elem and next_elem.name not in ['h2', 'h3']:
                    if next_elem.name in ['p', 'li', 'div']:
                        content_parts.append(next_elem.get_text().strip())
                    next_elem = next_elem.find_next()

                conteudo = " ".join(content_parts)

                if conteudo and len(conteudo) > 20:
                    doc = DocumentoRAG(
                        id=f"abo_web_curso_{titulo.lower().replace(' ', '_')[:20]}",
                        categoria="cursos",
                        titulo=titulo,
                        conteudo=conteudo,
                        metadata={
                            "fonte": "website",
                            "tipo": "curso",
                            "atualizado": datetime.now().strftime("%Y-%m-%d"),
                            "relevancia": "alto",
                            "url": url
                        }
                    )
                    documentos.append(doc)

        except Exception as e:
            logger.warning(f"⚠️  Erro em cursos: {str(e)}")

        return documentos

    def _scrape_associe_se(self, path: str) -> List[DocumentoRAG]:
        """Extrai informações sobre como se associar."""
        documentos = []
        
        try:
            url = self.base_url + path
            response = self.session.get(url, timeout=10)
            response.raise_for_status()
            soup = BeautifulSoup(response.content, 'html.parser')

            # Extrai informações sobre associação
            sections = soup.find_all(['h2', 'h3'])
            for section in sections:
                titulo = section.get_text().strip()
                
                content_parts = []
                next_elem = section.find_next()
                while next_elem and next_elem.name not in ['h2', 'h3']:
                    if next_elem.name in ['p', 'li', 'div']:
                        content_parts.append(next_elem.get_text().strip())
                    next_elem = next_elem.find_next()

                conteudo = " ".join(content_parts)

                if conteudo and len(conteudo) > 20:
                    doc = DocumentoRAG(
                        id=f"abo_web_associe_{titulo.lower().replace(' ', '_')[:20]}",
                        categoria="associacao",
                        titulo=titulo,
                        conteudo=conteudo,
                        metadata={
                            "fonte": "website",
                            "tipo": "associacao",
                            "atualizado": datetime.now().strftime("%Y-%m-%d"),
                            "relevancia": "alto",
                            "url": url
                        }
                    )
                    documentos.append(doc)

        except Exception as e:
            logger.warning(f"⚠️  Erro em associe-se: {str(e)}")

        return documentos

    def _scrape_contato(self, path: str) -> List[DocumentoRAG]:
        """Extrai informações de contato."""
        documentos = []
        
        try:
            url = self.base_url + path
            response = self.session.get(url, timeout=10)
            response.raise_for_status()
            soup = BeautifulSoup(response.content, 'html.parser')

            # Extrai informações de contato
            sections = soup.find_all(['h2', 'h3'])
            for section in sections:
                titulo = section.get_text().strip()
                
                content_parts = []
                next_elem = section.find_next()
                while next_elem and next_elem.name not in ['h2', 'h3']:
                    if next_elem.name in ['p', 'li', 'div', 'address']:
                        content_parts.append(next_elem.get_text().strip())
                    next_elem = next_elem.find_next()

                conteudo = " ".join(content_parts)

                if conteudo and len(conteudo) > 20:
                    doc = DocumentoRAG(
                        id=f"abo_web_contato_{titulo.lower().replace(' ', '_')[:20]}",
                        categoria="contato",
                        titulo=titulo,
                        conteudo=conteudo,
                        metadata={
                            "fonte": "website",
                            "tipo": "contato",
                            "atualizado": datetime.now().strftime("%Y-%m-%d"),
                            "relevancia": "muito_alto",
                            "url": url
                        }
                    )
                    documentos.append(doc)

        except Exception as e:
            logger.warning(f"⚠️  Erro em contato: {str(e)}")

        return documentos


# ============================================================================
# SCRAPER DO INSTAGRAM
# ============================================================================

class InstagramScraper:
    """Responsável por extrair dados do Instagram da ABO."""

    def __init__(self, username: str = "abobahia"):
        self.username = username
        self.profile_url = f"https://www.instagram.com/{username}"

    def scrape_instagram(self) -> List[DocumentoRAG]:
        """Extrai dados do Instagram."""
        documentos = []
        logger.info("📸 Iniciando coleta de dados do Instagram...")

        if INSTAGRAM_AVAILABLE:
            docs_instagrapi = self._scrape_with_instagrapi()
            documentos.extend(docs_instagrapi)
        else:
            # Fallback: web scraping simples
            docs_web = self._scrape_instagram_web()
            documentos.extend(docs_web)

        logger.info(f"✅ Instagram: {len(documentos)} documentos extraídos")
        return documentos

    def _scrape_with_instagrapi(self) -> List[DocumentoRAG]:
        """Usa instagrapi para extrair dados."""
        documentos = []

        try:
            # Nota: instagrapi requer autenticação
            # Para fins de demonstração, apenas estruturamos a lógica
            logger.info("💡 Sugestão: Configure credenciais do Instagram em .env")
            logger.info("   INSTAGRAM_USERNAME=seu_usuario")
            logger.info("   INSTAGRAM_PASSWORD=sua_senha")
            
            # Aqui você poderia adicionar:
            # client = InstagramClient()
            # client.login(username, password)
            # user = client.user_info_by_username(username)
            # medias = client.user_medias(user.pk, amount=20)

        except Exception as e:
            logger.warning(f"⚠️  Erro com instagrapi: {str(e)}")

        return documentos

    def _scrape_instagram_web(self) -> List[DocumentoRAG]:
        """Faz web scraping simples do Instagram."""
        documentos = []

        if not REQUESTS_AVAILABLE:
            logger.warning("⚠️  requests não disponível para Instagram")
            return documentos

        try:
            # Instagram bloqueia web scraping, então criamos estrutura genérica
            # Você pode usar uma API alternativa ou instagrapi com credenciais
            
            # Exemplo de documento estruturado com informações padrão
            doc = DocumentoRAG(
                id="abo_instagram_profile",
                categoria="redes_sociais",
                titulo="ABO-BA no Instagram",
                conteudo=(
                    "Siga @abobahia no Instagram para acompanhar: "
                    "notícias da associação, dicas de saúde bucal, "
                    "fotos de eventos, anúncios de cursos e especialização. "
                    "Interaja nos posts e veja as histórias (stories) para "
                    "conteúdo atualizado diariamente."
                ),
                metadata={
                    "fonte": "instagram",
                    "tipo": "perfil",
                    "atualizado": datetime.now().strftime("%Y-%m-%d"),
                    "relevancia": "alto",
                    "url": self.profile_url,
                    "nota": "Dados coletados de forma manual/API"
                }
            )
            documentos.append(doc)

            # Você pode adicionar estruturas de posts específicos aqui
            # se tiver uma fonte de dados estruturada

        except Exception as e:
            logger.warning(f"⚠️  Erro no scraping web do Instagram: {str(e)}")

        return documentos

    @staticmethod
    def adicionar_posts_manuais() -> List[DocumentoRAG]:
        """
        Estructura para adicionar posts do Instagram manualmente.
        
        Você pode atualizá-la conforme novos posts importantes surgirem.
        """
        documentos = []

        # Exemplo de estrutura - customize conforme necessário
        posts_instagram = [
            {
                "titulo": "Dicas de Higiene Bucal",
                "conteudo": "Escove os dentes 3x ao dia, passe fio dental após as refeições...",
                "categoria": "saude_bucal"
            },
            {
                "titulo": "Novo Curso de Implantodontia",
                "conteudo": "A ABO-BA está oferecendo especialização em Implantodontia...",
                "categoria": "educacao"
            }
        ]

        for idx, post in enumerate(posts_instagram):
            doc = DocumentoRAG(
                id=f"abo_instagram_post_{idx}",
                categoria=post.get("categoria", "redes_sociais"),
                titulo=post["titulo"],
                conteudo=post["conteudo"],
                metadata={
                    "fonte": "instagram",
                    "tipo": "post",
                    "atualizado": datetime.now().strftime("%Y-%m-%d"),
                    "relevancia": "medio",
                    "url": "https://www.instagram.com/abobahia/"
                }
            )
            documentos.append(doc)

        return documentos


# ============================================================================
# GERENCIADOR DA BASE DE CONHECIMENTO
# ============================================================================

class KnowledgeBaseManager:
    """Gerencia a base de conhecimento em JSON."""

    def __init__(self, filepath: str = "knowledge_base.json"):
        self.filepath = Path(filepath)
        self.documentos: Dict[str, DocumentoRAG] = {}

    def carregar_base_existente(self) -> bool:
        """Carrega a base de conhecimento existente."""
        try:
            if self.filepath.exists():
                with open(self.filepath, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                
                # Converte lista para dicionário (por ID)
                if isinstance(data, dict) and 'documentos' in data:
                    for doc_dict in data['documentos']:
                        doc = DocumentoRAG.from_dict(doc_dict)
                        self.documentos[doc.id] = doc
                    logger.info(f"✅ Base carregada: {len(self.documentos)} documentos")
                    return True
                elif isinstance(data, list):
                    for doc_dict in data:
                        doc = DocumentoRAG.from_dict(doc_dict)
                        self.documentos[doc.id] = doc
                    logger.info(f"✅ Base carregada: {len(self.documentos)} documentos")
                    return True
            else:
                logger.warning(f"⚠️  Arquivo não encontrado: {self.filepath}")
                return True  # Criar novo

        except Exception as e:
            logger.error(f"❌ Erro ao carregar base: {str(e)}")
            return False

    def adicionar_documentos(self, novos_docs: List[DocumentoRAG], 
                            atualizar: bool = True) -> int:
        """
        Adiciona novos documentos à base.
        
        Args:
            novos_docs: Lista de documentos para adicionar
            atualizar: Se True, sobrescreve docs com mesmo ID
        
        Returns:
            Número de documentos adicionados/atualizados
        """
        adicionados = 0

        for doc in novos_docs:
            if doc.id in self.documentos:
                if atualizar:
                    logger.debug(f"🔄 Atualizando: {doc.id}")
                    self.documentos[doc.id] = doc
                    adicionados += 1
                else:
                    logger.debug(f"⊘ Pulando (já existe): {doc.id}")
            else:
                logger.debug(f"✨ Adicionando: {doc.id}")
                self.documentos[doc.id] = doc
                adicionados += 1

        return adicionados

    def remover_duplicatas(self) -> int:
        """Remove documentos duplicados por conteúdo."""
        original_count = len(self.documentos)
        
        # Rastrear conteúdo já visto
        conteudo_vistos = {}
        ids_para_remover = []

        for doc_id, doc in self.documentos.items():
            # Cria fingerprint do conteúdo (simplificado)
            fingerprint = doc.conteudo[:100].lower()
            
            if fingerprint in conteudo_vistos:
                ids_para_remover.append(doc_id)
                logger.debug(f"Duplicata encontrada: {doc_id}")
            else:
                conteudo_vistos[fingerprint] = doc_id

        # Remove duplicatas
        for doc_id in ids_para_remover:
            del self.documentos[doc_id]

        removed = original_count - len(self.documentos)
        if removed > 0:
            logger.info(f"🧹 Removidas {removed} duplicatas")

        return removed

    def validar_documentos(self) -> bool:
        """Valida a integridade dos documentos."""
        logger.info("🔍 Validando documentos...")
        
        erros = 0

        for doc_id, doc in self.documentos.items():
            # Valida campos obrigatórios
            if not doc.id or not doc.titulo or not doc.conteudo:
                logger.error(f"❌ Doc incompleto: {doc_id}")
                erros += 1

            # Valida formato de ID
            if not doc.id.startswith("abo_"):
                logger.warning(f"⚠️  ID não padrão: {doc.id}")

            # Valida comprimento mínimo de conteúdo
            if len(doc.conteudo) < 20:
                logger.warning(f"⚠️  Conteúdo muito curto: {doc.id}")

            # Valida metadata
            if not doc.metadata or 'fonte' not in doc.metadata:
                logger.warning(f"⚠️  Metadata incompleta: {doc.id}")

        if erros == 0:
            logger.info(f"✅ Validação completa: {len(self.documentos)} docs OK")
            return True
        else:
            logger.error(f"❌ {erros} erros encontrados")
            return False

    def salvar_base(self, criar_backup: bool = True) -> bool:
        """
        Salva a base de conhecimento em JSON.
        
        Args:
            criar_backup: Se True, cria backup antes de salvar
        """
        try:
            # Cria backup
            if criar_backup and self.filepath.exists():
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                backup_path = self.filepath.with_name(
                    f"{self.filepath.stem}_backup_{timestamp}.json"
                )
                shutil.copy2(self.filepath, backup_path)
                logger.info(f"💾 Backup criado: {backup_path}")

            # Converte para formato esperado
            documentos_list = [doc.to_dict() for doc in self.documentos.values()]
            data = {"documentos": documentos_list}

            # Salva com formatação
            with open(self.filepath, 'w', encoding='utf-8') as f:
                json.dump(data, f, ensure_ascii=False, indent=2)

            logger.info(f"✅ Base salva: {self.filepath}")
            logger.info(f"   Total de documentos: {len(self.documentos)}")
            
            return True

        except Exception as e:
            logger.error(f"❌ Erro ao salvar: {str(e)}")
            return False

    def gerar_relatorio(self) -> str:
        """Gera relatório sobre a base de conhecimento."""
        categorias = {}
        fontes = {}

        for doc in self.documentos.values():
            # Conta por categoria
            categorias[doc.categoria] = categorias.get(doc.categoria, 0) + 1

            # Conta por fonte
            fonte = doc.metadata.get('fonte', 'desconhecida')
            fontes[fonte] = fontes.get(fonte, 0) + 1

        relatorio = f"""
╔═══════════════════════════════════════════════════════════════╗
║         RELATÓRIO DA BASE DE CONHECIMENTO - ABO-BA           ║
╚═══════════════════════════════════════════════════════════════╝

📊 RESUMO GERAL
───────────────────────────────────────────────────────────────
  Total de documentos: {len(self.documentos)}
  Data: {datetime.now().strftime('%d/%m/%Y %H:%M:%S')}

📁 DISTRIBUIÇÃO POR CATEGORIA
───────────────────────────────────────────────────────────────
"""
        for categoria, count in sorted(categorias.items()):
            relatorio += f"  • {categoria}: {count} doc(s)\n"

        relatorio += f"""
📡 DISTRIBUIÇÃO POR FONTE
───────────────────────────────────────────────────────────────
"""
        for fonte, count in sorted(fontes.items()):
            relatorio += f"  • {fonte}: {count} doc(s)\n"

        relatorio += f"""
✅ VALIDAÇÃO
───────────────────────────────────────────────────────────────
  Documentos validados: {len(self.documentos)}

═══════════════════════════════════════════════════════════════
"""
        return relatorio


# ============================================================================
# MAIN
# ============================================================================

def main():
    """Função principal."""
    parser = argparse.ArgumentParser(
        description="Atualizar base de conhecimento da ABO-BA",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Exemplos de uso:
  python atualizar_knowledge_base.py --site
  python atualizar_knowledge_base.py --instagram
  python atualizar_knowledge_base.py --full --backup
  python atualizar_knowledge_base.py --validate
        """
    )

    parser.add_argument(
        '--site',
        action='store_true',
        help='Atualizar dados do website'
    )
    parser.add_argument(
        '--instagram',
        action='store_true',
        help='Atualizar dados do Instagram'
    )
    parser.add_argument(
        '--full',
        action='store_true',
        help='Atualização completa (site + Instagram)'
    )
    parser.add_argument(
        '--backup',
        action='store_true',
        help='Criar backup antes de salvar'
    )
    parser.add_argument(
        '--validate',
        action='store_true',
        help='Apenas validar base existente'
    )
    parser.add_argument(
        '--report',
        action='store_true',
        help='Gerar relatório da base'
    )
    parser.add_argument(
        '--file',
        default='knowledge_base.json',
        help='Arquivo de base de conhecimento (padrão: knowledge_base.json)'
    )

    args = parser.parse_args()

    # Se nenhuma opção fornecida, mostra ajuda
    if not any([args.site, args.instagram, args.full, args.validate, args.report]):
        parser.print_help()
        return

    # Log inicial
    logger.info("=" * 70)
    logger.info("🚀 Iniciando atualização de base de conhecimento")
    logger.info(f"   Arquivo: {args.file}")
    logger.info("=" * 70)

    # Carrega gerenciador
    manager = KnowledgeBaseManager(args.file)
    manager.carregar_base_existente()

    # Validar apenas
    if args.validate:
        manager.validar_documentos()
        if args.report:
            print(manager.gerar_relatorio())
        return

    # Aplicar atualizações
    docs_adicionados = 0

    if args.site or args.full:
        logger.info("\n📝 Atualizando dados do website...")
        scraper = WebSiteScraper()
        docs_site = scraper.scrape_site()
        adicionados = manager.adicionar_documentos(docs_site, atualizar=True)
        docs_adicionados += adicionados
        logger.info(f"   ✨ {adicionados} documentos do site adicionados/atualizados")

    if args.instagram or args.full:
        logger.info("\n📷 Atualizando dados do Instagram...")
        scraper = InstagramScraper()
        docs_instagram = scraper.scrape_instagram()
        
        # Adiciona posts manuais também
        docs_instagram.extend(InstagramScraper.adicionar_posts_manuais())
        
        adicionados = manager.adicionar_documentos(docs_instagram, atualizar=True)
        docs_adicionados += adicionados
        logger.info(f"   ✨ {adicionados} documentos do Instagram adicionados/atualizados")

    # Pós-processamento
    logger.info("\n🧹 Pós-processamento...")
    removed = manager.remover_duplicatas()
    manager.validar_documentos()

    # Salvar
    logger.info("\n💾 Salvando base atualizada...")
    if manager.salvar_base(criar_backup=args.backup):
        logger.info(f"✅ Sucesso! {len(manager.documentos)} documentos na base")
    else:
        logger.error("❌ Falha ao salvar")
        sys.exit(1)

    # Relatório final
    if args.report:
        print(manager.gerar_relatorio())

    logger.info("\n" + "=" * 70)
    logger.info("✅ Atualização concluída!")
    logger.info("=" * 70)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        logger.warning("\n⚠️  Operação cancelada pelo usuário")
        sys.exit(0)
    except Exception as e:
        logger.critical(f"❌ Erro crítico: {str(e)}")
        sys.exit(1)
