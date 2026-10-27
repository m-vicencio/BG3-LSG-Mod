"""Modelos de datos devueltos por la API de producción de LifeSyncGames."""

from dataclasses import dataclass, field


@dataclass
class Dimension:
    """Representa una dimensión del Gemelo Digital Simplificado.

    Attributes:
        id: Identificador numérico de la dimensión (point_dimension_id).
        name: Nombre normalizado de la dimensión (ej. 'social', 'fisico').
        balance: Puntos acumulados en esta dimensión.
    """
    id: int
    name: str
    balance: int


@dataclass
class UserProfile:
    """Perfil completo del jugador autenticado en el sistema LSG.

    Attributes:
        player_id: Identificador único del jugador (id_players, entero).
        name: Nombre del jugador.
        email: Email del jugador.
        dimensions: Lista de dimensiones con sus balances de puntos.
    """
    player_id: int
    name: str
    email: str
    dimensions: list[Dimension] = field(default_factory=list)

    def balance_dict(self) -> dict[str, int]:
        """Retorna el balance como diccionario {nombre_dimensión: puntos}.

        Usado para serializar en session.json y para la firma HMAC.
        """
        return {dim.name: dim.balance for dim in self.dimensions}

    def balance_summary(self) -> str:
        """Retorna un resumen legible del balance multidimensional."""
        if not self.dimensions:
            return "Sin datos de dimensiones"
        return "  |  ".join(
            f"{dim.name.capitalize()}: {dim.balance:,}"
            for dim in self.dimensions
        )
